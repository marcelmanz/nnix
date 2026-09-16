#!/usr/bin/env python3
import datetime
import html
import json
import os
import subprocess
import sys
import time
import urllib.request
from urllib.parse import parse_qs
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

UNIT = "azuracast-live-capture"
REC_UNIT = "azuracast-live-record"
PORT = int(sys.argv[1])
AMIXER = sys.argv[2]
FFMPEG = sys.argv[3]
FFPROBE = sys.argv[4]
# webcam-control.py. It keeps owning the webcam state files, mediamtx's /authcheck and the
# public /status; this page only reads its /state and posts back through nginx's /cam/ route.
STREAMCAM_URL = f"http://127.0.0.1:{sys.argv[5]}"
# Same two inputs azuracast-live-record uses in live.nix - keep them in step if that changes.
RTSP_URL = "rtsp://127.0.0.1:8554/webcam"
# Cable 1 of snd-aloop: the same Scarlett+mic mix darkice gets on cable 0, duplicated by
# azuracast-live-mix so this page and the recorder can read it without fighting darkice.
# One capture client per cable, so the meter and the tests each get their own - cable 1
# belongs to azuracast-live-record and would be busy for the whole show.
METER_DEVICE = "plughw:CARD=Loopback,DEV=1,2"
MIX_DEVICE = "plughw:CARD=Loopback,DEV=1,3"
LEVEL_MS = 250
SYSTEMCTL = "/run/current-system/sw/bin/systemctl"
SUDO = "/run/wrappers/bin/sudo"
MIC_CONTROL = "Mic Capture Switch"
TEST_SECS = 4
STATE_DIR = Path(os.environ.get("STATE_DIRECTORY", "/var/lib/azuracast-live-web"))
TEST_FILE = STATE_DIR / "test-mic.mp3"
SYNC_FILE = STATE_DIR / "test-sync.mp4"
SYNC_SECS = 8
# Wider than any plausible darkice+liquidsoap lag; rejects fat-fingered input rather than
# letting a nonsense value silently break every recording.
OFFSET_LIMIT = 30.0
SHOWS_DIR = Path("/var/lib/media/live-recordings")
OFFSET_FILE = Path("/var/lib/azuracast-live-record/offset")
# Anything older than this and the recorder isn't actually writing - it's in its restart loop
# waiting for the camera to come back.
STALE_SECS = 30

PAGE = """<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Live</title>
<style>
* {{ box-sizing: border-box; }}
body {{ font-family: sans-serif; background: #111; color: #eee; margin: 0;
       min-height: 100vh; display: flex; flex-direction: column; }}
.stage {{ position: relative; flex: 1; min-height: 40vh; background: #000;
       display: flex; align-items: center; justify-content: center; }}
.stage video {{ width: 100%; height: 100%; max-height: 72vh; object-fit: contain; display: block; }}
.overlay {{ position: absolute; top: 0.75rem; left: 0.75rem; display: flex; gap: 0.5rem;
       flex-wrap: wrap; pointer-events: none; }}
.deck {{ display: flex; flex-direction: column; gap: 0.75rem; padding: 1rem;
       background: #181818; border-top: 1px solid #2a2a2a; }}
.group {{ display: flex; gap: 0.6rem; align-items: center; flex-wrap: wrap; }}
.group form {{ display: flex; gap: 0.4rem; align-items: center; margin: 0; }}
.badge {{ font-size: 0.8rem; font-weight: 700; letter-spacing: 0.06em; padding: 0.3rem 0.8rem;
       border-radius: 2rem; background: #555; }}
.live, .on {{ background: #2e7d32; }}
.offline, .off {{ background: #555; }}
.rec {{ background: #b71c1c; }}
.wait {{ background: #ef6c00; }}
button {{ font-size: 0.95rem; padding: 0.55rem 1.1rem; border-radius: 0.5rem; border: none;
       cursor: pointer; background: #333; color: #eee; }}
button:hover {{ background: #3d3d3d; }}
button.primary {{ background: #2e7d32; font-weight: 600; }}
button.danger {{ background: #b71c1c; font-weight: 600; }}
select, input {{ font-size: 0.95rem; padding: 0.5rem; border-radius: 0.4rem;
       border: 1px solid #444; background: #1c1c1c; color: #eee; }}
input[type=number] {{ width: 5.5rem; }}
label {{ font-size: 0.8rem; color: #888; text-transform: uppercase; letter-spacing: 0.08em; }}
.detail {{ font-size: 0.82rem; color: #aaa; line-height: 1.6; }}
.detail b {{ color: #eee; }}
.trk {{ display: inline-block; min-width: 3.2rem; color: #888; }}
.ok {{ color: #81c784; }}
.bad {{ color: #ef9a9a; }}
.err {{ color: #ef9a9a; font-size: 0.85rem; }}
.sep {{ flex: 1; }}
audio {{ height: 2.2rem; }}
.meter {{ width: min(60vw, 260px); height: 0.9rem; background: #222; border-radius: 0.45rem;
     overflow: hidden; border: 1px solid #333; }}
.meter i {{ display: block; height: 100%; width: 0%; background: #2e7d32; transition: width .12s; }}
.meter i.hot {{ background: #ef6c00; }}
.meter i.clip {{ background: #b71c1c; }}
#leveldb {{ font-variant-numeric: tabular-nums; color: #888; font-size: 0.8rem; min-width: 5.5rem; }}
.deck video {{ width: min(90vw, 420px); border-radius: 0.4rem; }}
</style></head>
<body>
<div class="stage">
  <video id="v" autoplay muted playsinline></video>
  <div class="overlay">
    <span class="badge {live_badge}" id="b-live">{live_status}</span>
    <span class="badge {rec_badge}" id="b-rec">{rec_status}</span>
    <span class="badge {pub_badge}" id="b-pub">Public: {pub_status}</span>
  </div>
</div>

<div class="deck">
  <div class="group">
    <form method="post" action="/toggle"><button class="{live_button_class}" id="a-live">{live_action}</button></form>
    <form method="post" action="/mic-toggle"><button id="a-mic">{mic_action}</button></form>
    <span class="badge {mic_badge}" id="b-mic">Mic {mic_status}</span>
    <div class="meter" title="desk mix level (Scarlett + mic)"><i id="levelbar"></i></div>
    <span id="leveldb">--</span>
    <span class="sep"></span>
    <form method="post" action="/cam/toggle"><button id="a-pub">{pub_action}</button></form>
    <form method="post" action="/cam/text-mode"><button>{text_action}</button></form>
  </div>

  <div class="group"><span class="detail" id="rec-detail">{rec_detail}</span></div>

  <div class="group">
    <form method="post" action="/offset">
      <label for="offset">A/V offset</label>
      <input id="offset" type="number" step="0.1" min="-{offset_limit}" max="{offset_limit}"
             name="offset" value="{offset}">
      <button>Save</button>
    </form>
    <form method="post" action="/test-sync"><button>Test sync ({sync_secs}s)</button></form>
    {offset_msg}
    {sync_result}
  </div>

  <div class="group">
    {cam_controls}
    <span class="sep"></span>
    <form method="post" action="/test-mic"><button>Test mic ({test_secs}s)</button></form>
    {test_result}
  </div>
</div>

<script>
// -60dB floor, so silence reads empty and speech sits around half.
(function poll() {{
  fetch("/level").then(function (r) {{ return r.json(); }}).then(function (j) {{
    var bar = document.getElementById("levelbar"), txt = document.getElementById("leveldb");
    if (j.db === null || j.db === undefined || j.db <= -90) {{
      bar.style.width = "0%"; bar.className = ""; txt.textContent = "silent";
    }} else {{
      bar.style.width = Math.max(0, Math.min(100, (j.db + 60) / 60 * 100)) + "%";
      bar.className = j.db > -1 ? "clip" : (j.db > -6 ? "hot" : "");
      txt.textContent = j.db.toFixed(1) + " dB";
    }}
  }}).catch(function () {{
    document.getElementById("leveldb").textContent = "no signal";
  }}).finally(function () {{ setTimeout(poll, 400); }});
}})();

(function pollStatus() {{
  fetch("/status.json").then(function (r) {{ return r.json(); }}).then(function (j) {{
    function badge(id, cls, text) {{
      var e = document.getElementById(id);
      if (e) {{ e.className = "badge " + cls; e.textContent = text; }}
    }}
    badge("b-live", j.live_badge, j.live_status);
    badge("b-rec", j.rec_badge, j.rec_status);
    badge("b-pub", j.pub_badge, "Public: " + j.pub_status);
    badge("b-mic", j.mic_badge, "Mic " + j.mic_status);
    var d = document.getElementById("rec-detail");
    if (d) d.innerHTML = j.rec_detail;
    var l = document.getElementById("a-live");
    if (l) {{ l.textContent = j.live_action; l.className = j.live_button_class; }}
    var m = document.getElementById("a-mic"); if (m) m.textContent = j.mic_action;
    var ef = document.getElementById("effect");
    if (ef) ef.disabled = j.recording;
    var en = document.getElementById("effect-note");
    if (en) en.style.display = j.recording ? "inline" : "none";
    var p = document.getElementById("a-pub"); if (p) p.textContent = j.pub_action;
  }}).catch(function () {{}}).finally(function () {{ setTimeout(pollStatus, 5000); }});
}})();

(async function () {{
  var pc = new RTCPeerConnection();
  pc.ontrack = function (e) {{ document.getElementById("v").srcObject = e.streams[0]; }};
  pc.addTransceiver("video", {{direction: "recvonly"}});
  var offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
  var res = await fetch("{whep_url}", {{
    method: "POST",
    headers: {{"Content-Type": "application/sdp"}},
    body: offer.sdp,
  }});
  if (!res.ok) return;
  var answer = await res.text();
  await pc.setRemoteDescription({{type: "answer", sdp: answer}});
}})().catch(function () {{}});
</script>
</body></html>
"""


def is_active() -> bool:
    return subprocess.run([SYSTEMCTL, "is-active", "--quiet", UNIT]).returncode == 0


def mic_on() -> bool:
    out = subprocess.run(
        [AMIXER, "-c", "Mic", "cget", f"name={MIC_CONTROL}"],
        capture_output=True,
        text=True,
        check=False,
    ).stdout
    return "values=on" in out


def set_mic(on: bool):
    subprocess.run(
        [AMIXER, "-c", "Mic", "cset", f"name={MIC_CONTROL}", "on" if on else "off"],
        check=False,
    )

CAM_CONTROLS = """
<form method="post" action="/cam/effect">
  <label>Effect</label>
  <select id="effect" name="effect" onchange="this.form.submit()"{effect_disabled}>{effect_options}</select>
  <span class="detail" id="effect-note" style="display:{effect_note_display}">locked while recording - a change would split the file</span>
</form>
<form method="post" action="/cam/offline-text">
  <label>Offline text</label>
  <input type="text" name="text" placeholder="{default_offline_text}"
         maxlength="{max_offline_text_len}" value="{offline_text}">
  <button>Save</button>
</form>
"""


def cam_state():
    try:
        with urllib.request.urlopen(f"{STREAMCAM_URL}/state", timeout=3) as resp:
            return json.load(resp)
    except Exception:
        return None


def cam_controls(state, recording: bool) -> str:
    if state is None:
        return '<span class="err">Webcam controls unavailable - is webcam-control-web running?</span>'
    options = "".join(
        f'<option value="{name}"{" selected" if name == state["effect"] else ""}>{name}</option>'
        for name in state["effects"]
    )
    return CAM_CONTROLS.format(
        effect_options=options,
        effect_disabled=" disabled" if recording else "",
        effect_note_display="inline" if recording else "none",
        default_offline_text=html.escape(state["default_offline_text"]),
        max_offline_text_len=state["max_offline_text_len"],
        offline_text=html.escape(state["offline_text"]),
    )


def read_offset() -> str:
    try:
        return OFFSET_FILE.read_text().strip()
    except OSError:
        return ""


def write_offset(raw: str) -> bool:
    """Reject anything that isn't a plausible number of seconds - this value goes straight
    into the recorder's -itsoffset, and a bad one silently desyncs every future show."""
    try:
        value = float(raw)
    except ValueError:
        return False
    if not -OFFSET_LIMIT <= value <= OFFSET_LIMIT:
        return False
    try:
        OFFSET_FILE.parent.mkdir(parents=True, exist_ok=True)
        OFFSET_FILE.write_text(f"{value:g}\n")
    except OSError:
        return False
    return True


def rec_active() -> bool:
    return subprocess.run([SYSTEMCTL, "is-active", "--quiet", REC_UNIT]).returncode == 0


def newest_show():
    try:
        shows = sorted(SHOWS_DIR.glob("*.mkv"), key=lambda f: f.stat().st_mtime)
    except OSError:
        return None
    return shows[-1] if shows else None


def human_size(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024


def human_secs(n: float) -> str:
    return f"{int(n) // 3600:02d}:{int(n) // 60 % 60:02d}:{int(n) % 60:02d}"


def started_at(show: Path):
    # The recorder names files with date +%F_%H%M%S, so the start time is the filename - no
    # need to ask ffprobe for a duration it can't know while the file is still being written.
    try:
        return datetime.datetime.strptime(show.stem, "%Y-%m-%d_%H%M%S")
    except ValueError:
        return None


def probe_tracks(show: Path) -> str:
    """One line per track. ffmpeg writes Matroska's Tracks element up front, so this reports
    correctly on a file that's still growing."""
    out = subprocess.run(
        [FFPROBE, "-v", "error", "-show_entries",
         "stream=codec_type,codec_name,width,height,r_frame_rate,sample_rate,channels",
         "-of", "json", str(show)],
        capture_output=True, text=True, check=False,
    ).stdout
    try:
        streams = json.loads(out)["streams"]
    except (ValueError, KeyError):
        return '<span class="bad">could not read tracks</span>'

    lines = []
    for kind, label in (("video", "video"), ("audio", "audio")):
        st = next((s for s in streams if s.get("codec_type") == kind), None)
        if st is None:
            lines.append(f'<span class="trk">{label}</span><span class="bad">missing</span>')
            continue
        if kind == "video":
            num, _, den = st.get("r_frame_rate", "0/1").partition("/")
            fps = float(num) / float(den) if float(den) else 0
            spec = f'{st.get("codec_name")} {st.get("width")}x{st.get("height")} {fps:g}fps'
        else:
            ch = {1: "mono", 2: "stereo"}.get(st.get("channels"), f'{st.get("channels")}ch')
            spec = f'{st.get("codec_name")} {st.get("sample_rate")} Hz {ch}'
        lines.append(f'<span class="trk">{label}</span><span class="ok">{spec}</span>')
    return "<br>".join(lines)


def offset_line() -> str:
    value = read_offset()
    if not value:
        return '<span class="bad">A/V offset not calibrated - audio will lag the video</span>'
    return f"A/V offset <b>{value}s</b>"


def recording_state():
    """(badge class, status text, detail html) for the recording panel."""
    show = newest_show()
    fresh = show is not None and time.time() - show.stat().st_mtime < STALE_SECS

    if not rec_active():
        if show is None:
            return "off", "IDLE", f"No recordings yet<br>{offset_line()}"
        start = started_at(show)
        length = human_secs(show.stat().st_mtime - start.timestamp()) if start else "?"
        return "off", "IDLE", (
            f"Last: <b>{show.name}</b><br>"
            f"{human_size(show.stat().st_size)} &middot; {length}<br>{offset_line()}"
        )

    if not fresh:
        # Unit is up but nothing is landing on disk: ffmpeg is in its 10s restart loop because
        # mediamtx has no webcam to hand it.
        return "wait", "WAITING FOR CAMERA", (
            "Recorder is running but no video is arriving.<br>"
            "Audio is still being captured by AzuraCast.<br>"
            f"{offset_line()}"
        )

    start = started_at(show)
    elapsed = human_secs(time.time() - start.timestamp()) if start else "?"
    return "rec", "REC", (
        f"<b>{show.name}</b><br>"
        f"{human_size(show.stat().st_size)} &middot; {elapsed}<br>"
        f"{probe_tracks(show)}<br>{offset_line()}"
    )


class Handler(BaseHTTPRequestHandler):
    def render(self, test_result="", sync_result="", offset_msg=""):
        live = is_active()
        mic = mic_on()
        cam = cam_state()
        rec_badge, rec_status, rec_detail = recording_state()
        html_page = PAGE.format(
            live_badge="live" if live else "offline",
            live_status="LIVE" if live else "OFFLINE",
            live_action="Stop streaming" if live else "Go live",
            live_button_class="danger" if live else "primary",
            mic_badge="on" if mic else "off",
            mic_status="ON" if mic else "MUTED",
            mic_action="Mute mic" if mic else "Unmute mic",
            pub_badge="on" if cam and cam["live"] else "off",
            pub_status="LIVE" if cam and cam["live"] else "hidden",
            pub_action=("Hide from public" if cam and cam["live"] else "Show on public"),
            text_action=(
                "Resume video" if cam and cam["text_mode"] else "Show text instead"
            ),
            cam_controls=cam_controls(cam, rec_badge == "rec"),
            whep_url=cam["whep_url"] if cam else "",
            rec_badge=rec_badge,
            rec_status=rec_status,
            rec_detail=rec_detail,
            offset=html.escape(read_offset()),
            offset_limit=f"{OFFSET_LIMIT:g}",
            sync_secs=SYNC_SECS,
            sync_result=sync_result,
            offset_msg=offset_msg,
            test_secs=TEST_SECS,
            test_result=test_result,
        )
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(html_page.encode())

    def serve_clip(self, path: Path, content_type: str):
        if not path.exists():
            self.send_response(404)
            self.end_headers()
            return
        data = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        route = self.path.split("?")[0]
        if route == "/level":
            # ffmpeg's volumedetect on a short grab. Cheap enough to poll, and it reads the
            # desk mix rather than the raw mic so it works while darkice holds cable 0.
            # A cable with no writer blocks the reader outright, so this must time out rather
            # than hang the poll - that's the "azuracast-live-mix is down" case.
            peak = None
            try:
                proc = subprocess.run(
                    [FFMPEG, "-nostdin", "-hide_banner", "-f", "alsa", "-ar", "44100",
                     "-ac", "2", "-i", METER_DEVICE, "-t", f"{LEVEL_MS / 1000:g}",
                     "-af", "volumedetect", "-f", "null", "-"],
                    capture_output=True, text=True, check=False, timeout=3,
                )
            except subprocess.TimeoutExpired:
                proc = None
            for line in (proc.stderr.splitlines() if proc else []):
                if "max_volume:" in line:
                    try:
                        peak = float(line.split("max_volume:")[1].strip().split()[0])
                    except (ValueError, IndexError):
                        pass
            body = json.dumps({"db": peak}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
            return
        if route == "/status.json":
            # Replaces the old meta-refresh. A full page reload tore down the WebRTC peer
            # connection every 10s - mediamtx logged a new session each time and the video
            # visibly stalled - so the page now updates these fields in place instead.
            cam = cam_state()
            rec_badge, rec_status, rec_detail = recording_state()
            live = is_active()
            mic = mic_on()
            body = json.dumps({
                "live": live, "live_status": "LIVE" if live else "OFFLINE",
                "live_badge": "live" if live else "offline",
                "live_action": "Stop streaming" if live else "Go live",
                "live_button_class": "danger" if live else "primary",
                "mic_badge": "on" if mic else "off",
                "mic_status": "ON" if mic else "MUTED",
                "mic_action": "Mute mic" if mic else "Unmute mic",
                "pub_badge": "on" if cam and cam["live"] else "off",
                "pub_status": "LIVE" if cam and cam["live"] else "hidden",
                "pub_action": "Hide from public" if cam and cam["live"] else "Show on public",
                "rec_badge": rec_badge, "rec_status": rec_status, "rec_detail": rec_detail,
                "recording": rec_badge == "rec",
            }).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
            return

        if route == "/test-mic.mp3":
            self.serve_clip(TEST_FILE, "audio/mpeg")
            return
        if route == "/test-sync.mp4":
            self.serve_clip(SYNC_FILE, "video/mp4")
            return
        self.render()

    def do_POST(self):
        if self.path == "/toggle":
            live = is_active()
            if not live:
                set_mic(True)
            action = "stop" if live else "start"
            subprocess.run([SUDO, SYSTEMCTL, action, UNIT], check=False)
            self.send_response(303)
            self.send_header("Location", "/")
            self.end_headers()
            return

        if self.path == "/offset":
            length = int(self.headers.get("Content-Length", 0))
            body = parse_qs(self.rfile.read(length).decode())
            raw = (body.get("offset") or [""])[0].strip()
            if write_offset(raw):
                self.send_response(303)
                self.send_header("Location", "/")
                self.end_headers()
                return
            # Don't redirect on failure - a silent bounce back to an unchanged field looks
            # exactly like a save that worked.
            self.render(offset_msg=(
                f'<span class="err">Could not save "{html.escape(raw)}" - '
                f"must be a number between -{OFFSET_LIMIT:g} and {OFFSET_LIMIT:g}, "
                "and /var/lib/azuracast-live-record/offset must be writable.</span>"
            ))
            return

        if self.path == "/test-sync":
            # The same two inputs the recorder uses, the same -itsoffset: clap on camera and
            # this tells you whether the offset lines them up. Reads the desk mix, so it works
            # without going on air. AAC because browsers won't play FLAC-in-MP4; video is
            # copied, so this costs nothing the recorder wouldn't already cost.
            offset = read_offset() or "0"
            # -itsoffset delays the video, so the clip's first `offset` seconds are audio-only.
            # Record that much extra or a 5s offset would leave 3s of usable overlap.
            try:
                duration = SYNC_SECS + max(0.0, float(offset))
            except ValueError:
                offset, duration = "0", float(SYNC_SECS)
            proc = subprocess.run(
                [FFMPEG, "-y", "-nostdin", "-hide_banner", "-loglevel", "error",
                 "-itsoffset", offset, "-rtsp_transport", "tcp", "-i", RTSP_URL,
                 "-f", "alsa", "-ar", "44100", "-ac", "2", "-i", MIX_DEVICE,
                 "-map", "0:v", "-map", "1:a", "-c:v", "copy", "-c:a", "aac", "-b:a", "160k",
                 "-t", f"{duration:g}", "-movflags", "+faststart", str(SYNC_FILE)],
                capture_output=True, check=False, timeout=duration + 30,
            )
            if proc.returncode == 0:
                result = (
                    f'<video controls autoplay src="/test-sync.mp4?t={int(time.time())}"></video>'
                )
            else:
                result = '<span class="err">Could not record - is the camera publishing?</span>'
            self.render(sync_result=result)
            return

        if self.path == "/mic-toggle":
            set_mic(not mic_on())
            self.send_response(303)
            self.send_header("Location", "/")
            self.end_headers()
            return

        if self.path == "/test-mic":
            # Reads the desk mix, not the raw mic device: azuracast-live-mix holds CARD=Mic
            # permanently now, so opening it here would always fail - and the mix is the more
            # useful thing to hear anyway, since it's what actually leaves the building.
            proc = subprocess.run(
                [
                    FFMPEG,
                    "-y",
                    "-f",
                    "alsa",
                    "-ar",
                    "44100",
                    "-ac",
                    "2",
                    "-i",
                    MIX_DEVICE,
                    "-t",
                    str(TEST_SECS),
                    "-c:a",
                    "libmp3lame",
                    "-b:a",
                    "128k",
                    str(TEST_FILE),
                ],
                capture_output=True,
                check=False,
            )
            if proc.returncode == 0:
                result = (
                    '<audio controls autoplay src="/test-mic.mp3?t='
                    + str(int(time.time()))
                    + '"></audio>'
                )
            else:
                result = '<p class="err">Could not record - is azuracast-live-mix running?</p>'
            self.render(test_result=result)
            return

        self.send_response(404)
        self.end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
