"""bandcampsync status page generator.

Three modes:
  generate    scan filesystem + last-run journal + urls.json -> index.html  (stdlib only)
  fetch-urls  hit bandcamp collection API -> urls.json  (needs bandcampsync importable)
  check       cheap poll (1 request) for a new purchase; exit 2 if collection changed

ponytail: note - run via python3, not shebang
"""

import html
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

HTML_DIR = Path("/var/lib/bandcampsync-status")
MUSIC_DIR = Path("/var/lib/media/music")
DJ_DIR = Path("/var/lib/media/dj")
URLS_JSON = HTML_DIR / "urls.json"
MADRID = ZoneInfo("Europe/Madrid")


def esc(s):
    return html.escape(str(s or ""))


def slug(s):
    s = re.sub(r"\s+", "-", (s or "")).lower()
    return re.sub(r"[^a-z0-9-]", "", s).strip("-")


def norm(s):
    """Loose match key: folder names are filesystem-sanitized (apostrophes stripped, etc.)
    and differ from the raw artist/album tags AzuraCast reports, so both sides normalize
    the same way before comparing."""
    s = (s or "").lower().replace("'", "").replace("’", "")
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9]+", " ", s)).strip()


def madrid(epoch):
    return datetime.fromtimestamp(epoch, MADRID).strftime("%Y-%m-%d %H:%M")


def systemctl(prop):
    r = subprocess.run(
        ["systemctl", "show", "-p", prop, "bandcampsync.service"],
        capture_output=True,
        text=True,
        check=False,
    )
    return r.stdout.split("=", 1)[1].strip() if "=" in r.stdout else ""


def last_run_journal(since):
    r = subprocess.run(
        [
            "journalctl",
            "-u",
            "bandcampsync.service",
            "--since",
            since,
            "--no-pager",
            "-o",
            "cat",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    return r.stdout


def load_urls():
    try:
        return json.loads(URLS_JSON.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def scan_albums():
    """id -> {ar, al, fmts:set, mtime} from bandcamp_item_id.txt files."""
    rows = {}
    for base, fmt in [(MUSIC_DIR, "flac"), (DJ_DIR, "aiff")]:
        for idf in base.rglob("bandcamp_item_id.txt"):
            item_id = idf.read_text().strip()
            album_dir = idf.parent
            artist_dir = album_dir.parent
            mtime = int(idf.stat().st_mtime)
            r = rows.setdefault(
                item_id,
                {
                    "ar": artist_dir.name,
                    "al": album_dir.name,
                    "fmts": set(),
                    "mtime": mtime,
                },
            )
            r["fmts"].add(fmt)
            r["mtime"] = min(r["mtime"], mtime)
    return rows


def parse_journal(journal):
    lines = journal.splitlines()
    flac = sum(1 for l in lines if "Moving extracted file" in l and l.endswith(".flac"))
    aiff = sum(1 for l in lines if "Moving extracted file" in l and l.endswith(".aiff"))
    skip_pre = sum(1 for l in lines if "preorder, skipping" in l)
    errors = sum(
        1
        for l in lines
        if ("[ERROR]" in l or "[WARNING]" in l)
        and "No valid notify target set" not in l
    )
    will = {}
    for l in lines:
        m = re.search(r'will download: "([^"]+)" \(id:(\d+)\)', l)
        if m:
            will[m.group(2)] = m.group(1)
    done = set(re.findall(r"Writing bandcamp item id:(\d+)", journal))
    pending = [(pid, name) for pid, name in will.items() if pid not in done]
    return flac, aiff, skip_pre, errors, pending, done


def build_links(rows, urls):
    """artist|album (normalized) -> exact bandcamp url, for albums we actually have a url for."""
    links = {}
    for item_id, r in rows.items():
        url = urls.get(item_id)
        if not url:
            continue
        links[f"{norm(r['ar'])}|{norm(r['al'])}"] = url
    return links


def generate():
    since = systemctl("ExecMainStartTimestamp")
    exit_code = systemctl("ExecMainStatus")
    journal = last_run_journal(since)
    urls = load_urls()
    rows = scan_albums()
    flac, aiff, skip_pre, errors, pending, done = parse_journal(journal)
    auth = "OK" if exit_code == "0" else "FAILED"
    albums = sorted(rows.items(), key=lambda kv: kv[1]["mtime"], reverse=True)

    o = []
    o.append(
        '<!doctype html><meta charset="utf-8">'
        '<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">'
        "<title>bandcampsync</title>"
    )
    o.append(
        "<style>body{font:14px system-ui;max-width:70em;margin:3em auto;padding:0 1em}"
        "table{border-collapse:collapse;width:100%}"
        "td,th{border:1px solid #ccc;padding:4px 8px;text-align:left}"
        ".ok{color:green}.pend{color:darkorange}.fail{color:red}"
        "td a{color:#0066cc;text-decoration:underline}td a:visited{color:#551a8b}"
        "</style>"
    )
    o.append("<h1>bandcampsync</h1>")
    cls = "ok" if auth == "OK" else "fail"
    o.append(
        f"<p><b>Auth:</b> <span class={cls}>{auth}</span> (exit {esc(exit_code)})"
        f" · <b>Last run:</b> {esc(since)}"
        f" · <b>Tracks:</b> flac {flac} aiff {aiff} · skipped preorders {skip_pre}"
        + (f" · <span class=fail>⚠ {errors} errors/warnings</span>" if errors else "")
        + "</p>"
    )
    added = [(iid, r) for iid, r in albums if iid in done]
    o.append(f"<h2>Added in last run ({len(added)})</h2>")
    if added:
        o.append(
            "<table><tr><th>Artist / Album</th><th>Added</th><th>Format(s)</th></tr>"
        )
        for item_id, r in added:
            url = (
                urls.get(item_id)
                or f"https://{slug(r['ar'])}.bandcamp.com/album/{slug(r['al'])}"
            )
            o.append(
                f"<tr><td><a href='{esc(url)}'>{esc(r['ar'])} / {esc(r['al'])}</a></td>"
                f"<td>{madrid(r['mtime'])}</td><td>{','.join(sorted(r['fmts']))}</td></tr>"
            )
        o.append("</table>")
    else:
        o.append("<p>none</p>")
    o.append(f"<h2>All albums ({len(albums)})</h2>")
    o.append(
        "<table><tr><th>Artist / Album</th><th>Status</th><th>Added</th><th>Format(s)</th></tr>"
    )
    for item_id, r in albums:
        url = (
            urls.get(item_id)
            or f"https://{slug(r['ar'])}.bandcamp.com/album/{slug(r['al'])}"
        )
        fmts = ",".join(sorted(r["fmts"]))
        o.append(
            f"<tr><td><a href='{esc(url)}'>{esc(r['ar'])} / {esc(r['al'])}</a></td>"
            f"<td class=ok>synced</td><td>{madrid(r['mtime'])}</td><td>{fmts}</td></tr>"
        )
    for pid, name in pending:
        url = urls.get(pid)
        link = f"<a href='{esc(url)}'>{esc(name)}</a>" if url else esc(name)
        o.append(
            f"<tr><td>{link}</td><td class=pend>pending</td><td>—</td><td>—</td></tr>"
        )
    o.append("</table>")
    o.append('<p><a href="last.log">Full log</a></p>')

    HTML_DIR.mkdir(parents=True, exist_ok=True)
    (HTML_DIR / "index.html").write_text("\n".join(o))
    (HTML_DIR / "last.log").write_text(journal)
    links = build_links(rows, urls)
    (HTML_DIR / "links.json").write_text(json.dumps(links))
    print(
        f"wrote index.html ({len(albums)} albums, {len(pending)} pending), links.json ({len(links)} links)"
    )


def fetch_urls():
    from bandcampsync.bandcamp import Bandcamp

    cookies = Path("/run/bandcamp_cookies_filtered.txt").read_text().strip()
    b = Bandcamp(cookies=cookies)
    b.verify_authentication()
    b.load_purchases()
    urls = {str(it.item_id): it._data.get("item_url") for it in b.purchases}
    URLS_JSON.write_text(json.dumps(urls, indent=2))
    print(f"wrote {len(urls)} urls")


LAST_ITEM_ID = HTML_DIR / "last_item_id.txt"


def check():
    """Fetch only the newest collection page (1 request) and compare its
    first item against the last seen one, so polling often stays cheap."""
    from bandcampsync.bandcamp import Bandcamp

    cookies = Path("/run/bandcamp_cookies_filtered.txt").read_text().strip()
    b = Bandcamp(cookies=cookies)
    b.verify_authentication()
    b.load_purchases(stop_when=lambda item: True)
    if not b.collection_items:
        print("empty collection")
        return
    newest_id = str(b.collection_items[0].item_id)
    last_id = LAST_ITEM_ID.read_text().strip() if LAST_ITEM_ID.exists() else None
    HTML_DIR.mkdir(parents=True, exist_ok=True)
    LAST_ITEM_ID.write_text(newest_id)
    if newest_id == last_id:
        print("unchanged")
        return
    print(f"new item id:{newest_id} (was {last_id})")
    sys.exit(2)


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "generate"
    if mode == "fetch-urls":
        fetch_urls()
    elif mode == "check":
        check()
    else:
        generate()
