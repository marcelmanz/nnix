"""Generate a spoken news bulletin from unread Miniflux entries and upload it to AzuraCast.

Every bulletin is also kept as mp3 in ARCHIVE_DIR with a static index.html listing it, which is
what https://bulletins.marcel.cool serves; the Monday run clears the previous week out.

Run twice a day by the azuracast-radio-bot systemd timer (see default.nix). All secrets and
endpoints arrive as environment variables; nothing is configured in this file.

What the station actually says lives in morning.md / afternoon.md - their
Intro and Outro are spoken verbatim and never reach the model, which only writes the middle.
"""

import html
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import numpy as np
import requests
import soundfile as sf

MINIFLUX_URL = os.environ.get("MINIFLUX_URL")
MINIFLUX_API_KEY = os.environ.get("MINIFLUX_API_KEY")
MINIFLUX_CATEGORY = os.environ.get("MINIFLUX_CATEGORY", "News")

SYNTHETIC_API_KEY = os.environ.get("SYNTHETIC_API_KEY")
SYNTHETIC_MODEL = os.environ.get("SYNTHETIC_MODEL", "syn:large:text")

AZURACAST_URL = os.environ.get("AZURACAST_URL")
AZURACAST_API_KEY = os.environ.get("AZURACAST_API_KEY")
AZURACAST_STATION = os.environ.get("AZURACAST_STATION", "radio_marcel")
AZURACAST_DIR = os.environ.get("AZURACAST_DIR", "news")

KOKORO_CONFIG = os.environ.get("KOKORO_CONFIG")
KOKORO_MODEL = os.environ.get("KOKORO_MODEL")
KOKORO_VOICE = os.environ.get("KOKORO_VOICE")
SPEED = float(os.environ.get("KOKORO_SPEED", "1.15"))

MORNING_DOC = os.environ.get("MORNING_DOC")
AFTERNOON_DOC = os.environ.get("AFTERNOON_DOC")

# Optional. A missing bed downgrades to a dry read rather than failing the bulletin.
BED_FILE = os.environ.get("BED_FILE")

# Optional. Bold ttf used to render each bulletin's cover art - "NEWS" plus the bulletin's
# date, what the player shows while it airs. No font = tag-only bulletin.
NEWS_ART_FONT = os.environ.get("NEWS_ART_FONT")

# Web archive of this week's bulletins. Served straight off disk by the bulletins.marcel.cool
# vhost in default.nix, so there is no service behind the page.
ARCHIVE_DIR = os.environ.get("ARCHIVE_DIR")

TZ = ZoneInfo(os.environ.get("TZ", "Europe/Madrid"))

REQUIRED = {
    "MINIFLUX_URL": MINIFLUX_URL,
    "MINIFLUX_API_KEY": MINIFLUX_API_KEY,
    "SYNTHETIC_API_KEY": SYNTHETIC_API_KEY,
    "AZURACAST_URL": AZURACAST_URL,
    "AZURACAST_API_KEY": AZURACAST_API_KEY,
    "KOKORO_CONFIG": KOKORO_CONFIG,
    "KOKORO_MODEL": KOKORO_MODEL,
    "KOKORO_VOICE": KOKORO_VOICE,
    "MORNING_DOC": MORNING_DOC,
    "AFTERNOON_DOC": AFTERNOON_DOC,
}

# The news slot is fifteen minutes (see program-plan.md), so there is room for a real
# bulletin rather than a handful of headlines. Anything past MAX_ENTRIES stays unread and leads
# the next run. FETCH_LIMIT is what the round-robin in by_source() picks from: Miniflux returns
# the newest entries overall, so a fetch the size of MAX_ENTRIES would often be one chatty feed.
MAX_ENTRIES = 24
MAX_CONTENT_CHARS = 800
FETCH_LIMIT = 250
SAMPLE_RATE = 24000

# Each blank line in the assembled script becomes this much silence, which is the only place the
# bed is allowed back up (see mix(): the compressor's release is longer than any gap between
# sentences, so short breaths never let the music in).
PAUSE_SECONDS = 2.6
INTRO_SECONDS = 7.0
OUTRO_SECONDS = 8.0
# The bed starts ducking this long before the first word, so music and voice never overlap on the
# way in - you hear the music drop, a beat of air, then the anchor. It has to stay comfortably
# longer than DUCK_ATTACK_MS or the fade would still be running over the opening syllables.
DUCK_LEAD_SECONDS = 1.4
# How gradually the music drops when the anchor comes back in after a pause. 15ms (a normal
# compressor setting) is audible as a hard clamp; this eases it into a musical fade instead.
DUCK_ATTACK_MS = 800
# How far the bed drops under the voice, and the only knob left for it: ffmpeg caps
# sidechaincompress ratio at 20, so depth comes from the threshold instead - every halving of it
# buys about 6dB more duck. 0.003 left the music audible under the anchor; this sits it further
# back without muting it. Raise it if the bed ever disappears entirely.
DUCK_THRESHOLD = 0.001
DUCK_RATIO = 20

miniflux_headers = {"X-Auth-Token": MINIFLUX_API_KEY}


def to_plain_text(markup):
    # ponytail: regex tag strip, not a parser. Feed is prose, and the anchor only ever reads the
    # model's rewrite of this - swap in html.parser if a feed starts leaking markup into audio.
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", markup))).strip()


def sanitise(text):
    """Strip the two things that have actually reached the synthesiser and broken it.

    `</think>`: syn:large:text leaks its reasoning tag into `content` even with
    reasoning_effort=none. Anything outside Latin: GLM is Chinese-trained and has emitted CJK
    mid-sentence ("the world's first 望远镜"), which the English phonemiser cannot voice at all.
    """
    text = re.sub(r"(?s)^.*?</think>", "", text)
    text = re.sub(r"[^\x00-\x7FÀ-ɏ‘’“”–—…]", "", text)
    return re.sub(r"[ \t]{2,}", " ", text).strip()


def say_spanish_properly(text):
    """Kokoro override so a stray "buenos dias" in the body is not read as "DIE-uhz"."""
    return re.sub(
        r"buenos\s+d[ií]as", "[Buenos días](/bwˈEnOs dˈiɑs/)", text, flags=re.IGNORECASE
    )


def read_doc(path):
    """Pull the Intro / Tone / Outro sections out of one of the markdown scripts."""
    sections = {}
    current = None
    with open(path, encoding="utf-8") as doc:
        for line in doc:
            heading = re.match(r"##\s+(\w+)\s*$", line)
            if heading:
                current = heading.group(1).lower()
                sections[current] = []
            elif current:
                sections[current].append(line)
    missing = {"intro", "tone", "outro"} - sections.keys()
    if missing:
        sys.exit(
            f"radio-bot: {path} is missing section(s): {', '.join(sorted(missing))}"
        )
    return {k: "".join(v).strip() for k, v in sections.items()}


def category_id():
    res = requests.get(
        f"{MINIFLUX_URL}/v1/categories", headers=miniflux_headers, timeout=10
    )
    res.raise_for_status()
    categories = res.json()
    for category in categories:
        if category["title"].lower() == MINIFLUX_CATEGORY.lower():
            return category["id"]
    titles = ", ".join(sorted(c["title"] for c in categories))
    sys.exit(f"No Miniflux category named {MINIFLUX_CATEGORY!r}. Available: {titles}")


def by_source(entries, limit):
    """Round-robin across feeds so every source in the category makes it on air.

    Miniflux hands back the newest entries overall, and one busy feed can own that whole list -
    the bulletin then covers two sources and ignores the rest. Taking one entry per feed at a
    time keeps the quiet sources represented while still preferring the newest of each.
    """
    queues = {}
    for entry in entries:
        queues.setdefault((entry.get("feed") or {}).get("id"), []).append(entry)
    picked = []
    while len(picked) < limit and any(queues.values()):
        for queue in queues.values():
            if queue and len(picked) < limit:
                picked.append(queue.pop(0))
    return picked


def unread_entries():
    res = requests.get(
        f"{MINIFLUX_URL}/v1/categories/{category_id()}/entries",
        params={"status": "unread", "limit": FETCH_LIMIT, "direction": "desc"},
        headers=miniflux_headers,
        timeout=30,
    )
    res.raise_for_status()
    return by_source(res.json().get("entries", []), MAX_ENTRIES)


def write_body(entries, doc, now):
    """The model writes only the middle; the intro and outro never reach it."""
    items = "\n".join(
        f"- {e['title']}: {to_plain_text(e.get('content', ''))[:MAX_CONTENT_CHARS]}"
        for e in entries
    )
    prompt = (
        f"You are the host of Radio Marcel, a personal radio station. It is {now:%A %d %B %Y}. "
        f"{doc['tone']}\n\n"
        "Never mention a national holiday, a bank holiday, a long weekend, a season, or the "
        "weather where the listener might be, and never wish them anything tied to one. Report "
        "what happened, not where the listener supposedly is.\n\n"
        "Deaths, violence, grief and victims are the one thing you never joke about: report "
        "those plainly and briefly, then move on. Everything else is fair game.\n\n"
        "You are writing ONLY the middle of a bulletin. A greeting has already been spoken "
        "before your first word and a sign-off will be spoken after your last, so write "
        "neither. Your final sentence must be an ordinary news sentence: never end with 'that "
        "is it', 'that is all', 'I am done', 'that is your bulletin' or any other closing "
        "remark. Cover every item below - each one comes from a different corner of the "
        "listener's feeds and none may be dropped, however minor it looks. Give each story two "
        "to four sentences: what happened, and why it matters. Group closely related stories "
        "together and separate each story or group with a blank line. Each story appears once "
        "and once only: never mention the same event twice.\n\n"
        "Output only the words to be read aloud: no URLs, no markdown, no headings, no stage "
        "directions, no emoji. Never refer to your instructions, to rules you have been given, "
        "or to what you have been told or asked to do - the listener must never learn that any "
        "of this exists.\n\n" + items
    )
    res = requests.post(
        "https://api.synthetic.new/v1/chat/completions",
        headers={"Authorization": f"Bearer {SYNTHETIC_API_KEY}"},
        json={
            "model": SYNTHETIC_MODEL,
            "messages": [{"role": "user", "content": prompt}],
            "reasoning_effort": "none",
            # A full-length bulletin is a few thousand tokens; without this the provider default
            # cuts the read off mid-story.
            "max_tokens": 8000,
        },
        timeout=300,
    )
    res.raise_for_status()
    return say_spanish_properly(
        sanitise(res.json()["choices"][0]["message"]["content"])
    )


def paragraphs(text):
    return [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]


SIGNOFF = re.compile(
    r"\b(that(?:'| i)s (?:your |the )?(?:lot|it|all|bulletin)"
    r"|i(?:'| a)m (?:done|off|out of here)"
    r"|over and out|see you|catch you|until (?:next|tomorrow))\b",
    re.IGNORECASE,
)


def drop_trailing_signoff(body):
    """The model writes its own ending anyway, however firmly the prompt forbids it.

    Left alone the bulletin closes twice: the model's invented sign-off, then the verbatim Outro
    from the markdown. Only the last paragraph is considered, and only a short one, so a genuine
    news item that happens to contain the words survives.
    """
    paras = paragraphs(body)
    if len(paras) > 1 and len(paras[-1]) < 300 and SIGNOFF.search(paras[-1]):
        print(f"radio-bot: dropped a model sign-off: {paras[-1][:80]!r}")
        return "\n\n".join(paras[:-1])
    return body


def synthesize(script, wav_path):
    """One paragraph per pipeline run, joined by real silence.

    Those silences are what the bed swells into, so they are the structure of the piece, not
    cosmetic padding.
    """
    from kokoro import KModel, KPipeline

    model = KModel(
        repo_id="hexgrad/Kokoro-82M", config=KOKORO_CONFIG, model=KOKORO_MODEL
    ).eval()
    pipe = KPipeline(lang_code="a", repo_id="hexgrad/Kokoro-82M", model=model)

    gap = np.zeros(int(PAUSE_SECONDS * SAMPLE_RATE), dtype=np.float32)
    pieces = []
    for para in paragraphs(script):
        chunks = [r.audio.numpy() for r in pipe(para, voice=KOKORO_VOICE, speed=SPEED)]
        if not chunks:
            continue
        if pieces:
            pieces.append(gap)
        pieces.append(np.concatenate(chunks))
    if not pieces:
        sys.exit("radio-bot: synthesiser produced no audio")
    sf.write(wav_path, np.concatenate(pieces), SAMPLE_RATE)


def mix(vox_path, out_path):
    """Lay the voice over a ducked music bed.

    release=2600ms is the whole trick: it is longer than any gap between sentences, so the bed
    stays down through the read and only climbs back during the deliberate PAUSE_SECONDS breaks
    and at the two ends. The sidechain key is the voice shifted DUCK_LEAD_SECONDS earlier, so the
    music is already out of the way before the first word lands.
    """
    duration = sf.info(vox_path).duration
    total = round(duration + INTRO_SECONDS + OUTRO_SECONDS, 2)
    lead = int((INTRO_SECONDS - DUCK_LEAD_SECONDS) * 1000)
    fmt = f"aformat=sample_fmts=fltp:sample_rates={SAMPLE_RATE}:channel_layouts=mono"
    graph = (
        f"[0:a]{fmt},volume=1.4,adelay={int(INTRO_SECONDS * 1000)},apad[vox];"
        f"[0:a]{fmt},adelay={lead},apad[key];"
        f"[1:a]{fmt},volume=0.5,afade=t=in:st=0:d=2,"
        f"afade=t=out:st={round(total - 3, 2)}:d=3[bedraw];"
        "[bedraw][key]sidechaincompress="
        f"threshold={DUCK_THRESHOLD}:ratio={DUCK_RATIO}:attack={DUCK_ATTACK_MS}:"
        "release=2600:makeup=1[bed];"
        "[bed][vox]amix=inputs=2:duration=first:dropout_transition=0,"
        "alimiter=limit=0.95,aformat=sample_fmts=s16[out]"
    )
    cmd = ["ffmpeg", "-y", "-v", "error", "-i", vox_path]
    cmd += ["-stream_loop", "-1", "-i", BED_FILE]
    cmd += ["-filter_complex", graph, "-map", "[out]", "-t", str(total), out_path]
    subprocess.run(cmd, check=True)


def bulletin_meta(now):
    """The ID3 title (what the player displays) and uploaded filename for one bulletin."""
    slot = "Morning News" if now.hour < 12 else "Afternoon News"
    title = f"{slot} - {now:%A %d %B}"
    return title, f"{title} {now:%H%M}.mp3"


def archived_at(name):
    """The timestamp encoded in an archive filename, or None if the file is not one of ours."""
    try:
        return datetime.strptime(os.path.splitext(name)[0], "%Y-%m-%d-%H%M")
    except ValueError:
        return None


def expired(names, cutoff):
    """Archived bulletins from before `cutoff`.

    main() passes this week's Monday, so a Monday run is the one that clears last week out and
    every other run finds nothing to do - no separate timer needed for the weekly sweep.
    """
    return [n for n in names if (archived_at(n) or datetime.max).date() < cutoff]


def slot_label(name):
    return "morning bulletin" if archived_at(name).hour < 12 else "afternoon bulletin"


def render_index(names):
    """One self-contained page: a section per day, newest first, with a player per bulletin.

    Plain text on plain background, light or dark by browser preference. `color-scheme` is what
    makes the native <audio> controls follow along - without it they stay light on a dark page.
    """
    days = {}
    for name in names:
        days.setdefault(name[:10], []).append(name)
    sections = "\n".join(
        "<section><h2>{day:%A %-d %B}</h2><ul>{rows}</ul></section>".format(
            day=datetime.strptime(day, "%Y-%m-%d"),
            rows="".join(
                f"<li><p>{archived_at(n):%H:%M} {slot_label(n)}</p>"
                f'<audio controls preload="none" src="{n}"></audio></li>'
                for n in sorted(days[day])
            ),
        )
        for day in sorted(days, reverse=True)
    )
    return (
        "<!doctype html>\n"
        '<html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        "<title>Radio Marcel - news bulletins</title><style>"
        ":root{color-scheme:light dark;--bg:#fff;--fg:#1a1a1a;--dim:#666;--line:#ddd}"
        "@media(prefers-color-scheme:dark){"
        ":root{--bg:#2b2b2b;--fg:#eaeaea;--dim:#aaa;--line:#444}}"
        "body{margin:0;padding:2rem 1.25rem;background:var(--bg);color:var(--fg);"
        "font:16px/1.6 system-ui,sans-serif}"
        "main{max-width:36rem;margin:0 auto}"
        "h1{margin:0;font-size:1.25rem;font-weight:600}"
        "p.sub{margin:.25rem 0 2rem;color:var(--dim)}"
        "h2{margin:2rem 0 .5rem;padding-bottom:.3rem;font-size:1rem;font-weight:600;"
        "border-bottom:1px solid var(--line)}"
        "ul{list-style:none;margin:0;padding:0}"
        "li{margin:0 0 1rem}"
        "li p{margin:0 0 .3rem;color:var(--dim)}"
        "audio{width:100%}"
        "a{color:inherit}"
        "</style></head><body><main>"
        '<h1><a href="https://radio.marcel.cool">Radio Marcel</a> news</h1>'
        '<p class="sub">This week\'s bulletins. Cleared every Monday.</p>'
        + (sections or "<p>Nothing archived yet.</p>")
        + "</main></body></html>\n"
    )


def make_news_art(path, now):
    """Per-bulletin cover art: 'NEWS' plus the bulletin's date, in the player's neon palette."""
    vf = (
        "drawbox=x=0:y=0:w=1000:h=14:color=0xff3df0@1:t=fill,"
        f"drawtext=fontfile={NEWS_ART_FONT}:text='NEWS':fontcolor=white:fontsize=250:"
        "x=(w-text_w)/2:y=360,"
        f"drawtext=fontfile={NEWS_ART_FONT}:text='{now:%A %-d %B}':fontcolor=0xffe600:"
        "fontsize=72:x=(w-text_w)/2:y=660"
    )
    subprocess.run(
        ["ffmpeg", "-y", "-v", "error", "-f", "lavfi",
         "-i", "color=c=0x14141e:s=1000x1000,format=rgb24",
         "-vf", vf, "-frames:v", "1", path],
        check=True,
    )


def to_mp3(wav_path, mp3_path, title, art=None):
    """Tagged mp3 that AzuraCast airs and bulletins.marcel.cool serves - one encode for both.

    The wav a bulletin starts as is ~22MB of 24kHz mono; mp3 at -q:a 5 more than halves that and
    both consumers are fine with it. The ID3 title is what the player shows instead of a raw
    filename, and the embedded picture (make_news_art renders it) is its album art. mp3 (not the
    wav muxer) is the only ffmpeg container that carries the picture as a plain flag rather than
    hand-built ID3 bytes.
    """
    cmd = ["ffmpeg", "-y", "-v", "error", "-i", wav_path]
    if art and os.path.exists(art):
        cmd += [
            "-i", art, "-map", "0:a", "-map", "1:v",
            "-c:v", "copy", "-disposition:v", "attached_pic",
            "-metadata:s:v", "comment=Cover (front)",
        ]
    cmd += [
        "-codec:a", "libmp3lame", "-q:a", "5", "-ac", "1",
        "-id3v2_version", "3",
        "-metadata", f"title={title}",
        mp3_path,
    ]
    subprocess.run(cmd, check=True)


def archive(mp3_path, now):
    """Keep the week's bulletins on disk and rewrite the page that lists them.

    The mp3 already exists (to_mp3 made it for the upload), so archiving is a plain copy. Names
    are parsed by archived_at() and the page is served as-is by nginx.
    """
    os.makedirs(ARCHIVE_DIR, exist_ok=True)
    name = f"{now:%Y-%m-%d-%H%M}.mp3"
    shutil.copy(mp3_path, os.path.join(ARCHIVE_DIR, name))
    monday = now.date() - timedelta(days=now.weekday())
    for stale in expired(os.listdir(ARCHIVE_DIR), monday):
        os.remove(os.path.join(ARCHIVE_DIR, stale))
        print(f"radio-bot: dropped last week's {stale}")
    names = [n for n in os.listdir(ARCHIVE_DIR) if archived_at(n)]
    with open(os.path.join(ARCHIVE_DIR, "index.html"), "w", encoding="utf-8") as page:
        page.write(render_index(names))
    print(f"radio-bot: archived {name}, {len(names)} bulletin(s) on the page")


def upload(mp3_path, name):
    with open(mp3_path, "rb") as mp3:
        res = requests.post(
            f"{AZURACAST_URL}/api/station/{AZURACAST_STATION}/files/upload",
            headers={"X-API-Key": AZURACAST_API_KEY},
            data={"currentDirectory": AZURACAST_DIR},
            files={"file": (name, mp3, "audio/mpeg")},
            timeout=300,
        )
    res.raise_for_status()


def stale_paths(rows, keep_path):
    # .wav as well: bulletins uploaded before the mp3 switch must not linger in the playlist.
    return [
        r["path"]
        for r in rows
        if r["path"].endswith((".wav", ".mp3")) and r["path"] != keep_path
    ]


def prune(keep_path):
    """Drop every bulletin but the newest.

    The news playlist is scheduled rather than shuffled, so anything left in the folder is a
    stale bulletin the 08:00/17:00 windows could air instead of today's. Only files this
    script uploaded ever live here.
    """
    res = requests.get(
        f"{AZURACAST_URL}/api/station/{AZURACAST_STATION}/files/list",
        params={"currentDirectory": AZURACAST_DIR},
        headers={"X-API-Key": AZURACAST_API_KEY},
        timeout=60,
    )
    res.raise_for_status()
    stale = stale_paths(res.json(), keep_path)
    if not stale:
        return
    res = requests.put(
        f"{AZURACAST_URL}/api/station/{AZURACAST_STATION}/files/batch",
        headers={"X-API-Key": AZURACAST_API_KEY},
        json={"do": "delete", "files": stale, "dirs": []},
        timeout=120,
    )
    res.raise_for_status()
    print(f"radio-bot: pruned {len(stale)} stale bulletin(s)")


def mark_read(entries):
    res = requests.put(
        f"{MINIFLUX_URL}/v1/entries",
        headers=miniflux_headers,
        json={"entry_ids": [e["id"] for e in entries], "status": "read"},
        timeout=30,
    )
    res.raise_for_status()


def self_check():
    assert to_plain_text("<p>Hello &amp;   <b>world</b></p>") == "Hello & world"
    assert to_plain_text("") == ""

    rows = [
        {"path": "news/older.wav"},
        {"path": "news/old.mp3"},
        {"path": "news/new.mp3"},
        {"path": "news/cover.jpg"},
    ]
    assert stale_paths(rows, "news/new.mp3") == ["news/older.wav", "news/old.mp3"]
    assert stale_paths([{"path": "news/new.mp3"}], "news/new.mp3") == []

    title, name = bulletin_meta(datetime(2026, 8, 31, 8, 0))
    assert title == "Morning News - Monday 31 August" and name == (
        "Morning News - Monday 31 August 0800.mp3"
    )
    assert bulletin_meta(datetime(2026, 8, 31, 17, 0))[0] == (
        "Afternoon News - Monday 31 August"
    )

    feed_a = {"id": 1}
    feed_b = {"id": 2}
    mixed = [
        {"id": 1, "feed": feed_a},
        {"id": 2, "feed": feed_a},
        {"id": 3, "feed": feed_a},
        {"id": 4, "feed": feed_b},
    ]
    assert [e["id"] for e in by_source(mixed, 4)] == [1, 4, 2, 3]
    assert [e["id"] for e in by_source(mixed, 2)] == [1, 4]
    assert by_source([], 5) == []

    assert sanitise("<think>hmm</think>Real text") == "Real text"
    assert sanitise("first 望远镜 telescope") == "first telescope"
    assert sanitise("café naïve") == "café naïve"

    assert say_spanish_properly("Buenos dias, all").startswith("[Buenos días](/")
    assert say_spanish_properly("no greeting here") == "no greeting here"

    week = ["2026-08-24-0800.mp3", "2026-08-31-0800.mp3", "2026-08-31-1700.mp3"]
    assert expired(week + ["index.html"], datetime(2026, 8, 31).date()) == [
        "2026-08-24-0800.mp3"
    ]
    assert expired(week, datetime(2026, 8, 24).date()) == []
    assert slot_label(week[1]) == "morning bulletin"
    assert slot_label(week[2]) == "afternoon bulletin"

    page = render_index(week)
    assert page.count("<section>") == 2 and page.count("<audio") == 3
    assert page.index("2026-08-31-0800.mp3") < page.index("2026-08-24-0800.mp3")
    assert "Nothing archived yet" in render_index([])

    assert paragraphs("one\n\ntwo\n\n\nthree") == ["one", "two", "three"]
    assert paragraphs("  ") == []

    assert (
        drop_trailing_signoff("News one.\n\nThat's your lot. I need a drink.")
        == "News one."
    )
    keep = "News one.\n\nHe inherited a lot of debt and it is all still unpaid."
    assert drop_trailing_signoff(keep) == keep
    assert drop_trailing_signoff("That is it.") == "That is it."
    print("self-check ok")


def main():
    if "--self-check" in sys.argv:
        return self_check()

    missing = [k for k, v in REQUIRED.items() if not v]
    if missing:
        sys.exit(f"radio-bot: missing environment variables: {', '.join(missing)}")

    now = datetime.now(TZ)
    doc = read_doc(MORNING_DOC if now.hour < 12 else AFTERNOON_DOC)

    entries = unread_entries()
    if not entries:
        print("radio-bot: no unread entries, nothing to broadcast")
        return

    body = drop_trailing_signoff(write_body(entries, doc, now))
    script = "\n\n".join([doc["intro"], body, doc["outro"]])

    title, name = bulletin_meta(now)
    dry_run = "--dry-run" in sys.argv
    with tempfile.TemporaryDirectory() as tmp:
        vox_path = os.path.join(tmp, "vox.wav")
        mixed_path = os.path.join(tmp, "mixed.wav")
        mp3_path = os.path.abspath(name) if dry_run else os.path.join(tmp, name)
        synthesize(script, vox_path)
        art_path = None
        if NEWS_ART_FONT and os.path.exists(NEWS_ART_FONT):
            art_path = os.path.join(tmp, "art.jpg")
            make_news_art(art_path, now)
        if BED_FILE and os.path.exists(BED_FILE):
            mix(vox_path, mixed_path)
        else:
            print(f"radio-bot: no bed at {BED_FILE!r}, uploading a dry read")
            mixed_path = vox_path
        to_mp3(mixed_path, mp3_path, title, art_path)
        if dry_run:
            # preview only: nothing airs, and the entries stay unread for the real run
            print(f"radio-bot: dry run, wrote {mp3_path}\n\n{script}")
            return
        upload(mp3_path, name)
        if ARCHIVE_DIR:
            archive(mp3_path, now)

    mark_read(entries)
    print(f"radio-bot: uploaded {AZURACAST_DIR}/{name} from {len(entries)} entries")
    prune(f"{AZURACAST_DIR}/{name}")


if __name__ == "__main__":
    main()
