#!/usr/bin/env python3
import html
import json
import secrets
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs

PORT = int(sys.argv[1])
STATE_FILE = Path(sys.argv[2])
TOKEN_FILE = STATE_FILE.parent / "preview-token"
EFFECT_FILE = STATE_FILE.parent / "effect"
OFFLINE_TEXT_FILE = STATE_FILE.parent / "offline-text"
DEFAULT_OFFLINE_TEXT = "Off air"
MAX_OFFLINE_TEXT_LEN = 100
WHEP_PATH = "/webcam/whep"

# ffmpeg -vf filter per effect name; webcam.nix's runOnInit reads EFFECT_FILE's
# raw value straight into -vf, so this is the single source of truth for both.
EFFECTS = {
    "none": "null",
    "grayscale": "hue=s=0",
    "sepia": "colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131",
    "invert": "negate",
    "edge": "edgedetect",
    "vintage": "curves=vintage,vignette",
}

PAGE = """<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Webcam test</title>
<style>
body {{ font-family: sans-serif; background: #111; color: #eee; display: flex; flex-direction: column;
       align-items: center; justify-content: center; min-height: 100vh; margin: 0; gap: 1.5rem; padding: 1rem; }}
video {{ width: min(90vw, 640px); background: #000; border-radius: 0.5rem; }}
.badge {{ font-size: 1.25rem; padding: 0.4rem 1.2rem; border-radius: 2rem; }}
.live {{ background: #2e7d32; }}
.offline {{ background: #555; }}
button {{ font-size: 1.25rem; padding: 0.8rem 1.6rem; border-radius: 0.5rem; border: none; cursor: pointer; }}
</style></head>
<body>
<video id="v" autoplay muted playsinline controls></video>
<div class="badge {badge_class}">Public page: {status}</div>
<form method="post" action="/toggle"><button>{action}</button></form>
<form method="post" action="/effect">
  <select name="effect" onchange="this.form.submit()">{effect_options}</select>
</form>
<form method="post" action="/offline-text">
  <input type="text" name="text" placeholder="{default_offline_text}" maxlength="{max_offline_text_len}" value="{offline_text}">
  <button>Save offline text</button>
</form>
<script>
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


def is_live() -> bool:
    return STATE_FILE.exists()


def preview_token() -> str:
    if not TOKEN_FILE.exists():
        TOKEN_FILE.write_text(secrets.token_urlsafe(24))
    return TOKEN_FILE.read_text().strip()


def current_effect() -> str:
    value = EFFECT_FILE.read_text().strip() if EFFECT_FILE.exists() else EFFECTS["none"]
    return next((name for name, filt in EFFECTS.items() if filt == value), "none")


def current_offline_text() -> str:
    if OFFLINE_TEXT_FILE.exists():
        text = OFFLINE_TEXT_FILE.read_text().strip()
        if text:
            return text
    return DEFAULT_OFFLINE_TEXT


class Handler(BaseHTTPRequestHandler):
    def render(self):
        live = is_live()
        current = current_effect()
        options = "".join(
            f'<option value="{name}"{" selected" if name == current else ""}>{name}</option>'
            for name in EFFECTS
        )
        whep_url = f"https://radio.marcel.cool{WHEP_PATH}?preview={preview_token()}"
        stored_offline_text = OFFLINE_TEXT_FILE.read_text().strip() if OFFLINE_TEXT_FILE.exists() else ""
        page = PAGE.format(
            badge_class="live" if live else "offline",
            status="LIVE" if live else "hidden",
            action="Stop showing on public page" if live else "Show on public page",
            effect_options=options,
            whep_url=whep_url,
            default_offline_text=html.escape(DEFAULT_OFFLINE_TEXT),
            max_offline_text_len=MAX_OFFLINE_TEXT_LEN,
            offline_text=html.escape(stored_offline_text),
        )
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(page.encode())

    def do_GET(self):
        if self.path == "/status":
            body = json.dumps({"live": is_live(), "offline_text": current_offline_text()}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
            return
        self.render()

    def do_POST(self):
        if self.path == "/toggle":
            if is_live():
                STATE_FILE.unlink(missing_ok=True)
            else:
                STATE_FILE.touch()
            self.send_response(303)
            self.send_header("Location", "/")
            self.end_headers()
            return

        if self.path == "/effect":
            length = int(self.headers.get("Content-Length", 0))
            body = parse_qs(self.rfile.read(length).decode())
            effect = (body.get("effect") or [None])[0]
            if effect in EFFECTS:
                EFFECT_FILE.write_text(EFFECTS[effect])
                # ponytail: applies the new filter by restarting all of mediamtx (brief
                # reconnect for any viewer); switch to signalling just the ffmpeg publisher
                # if that drop ever becomes annoying.
                # /run/wrappers/bin: service PATH lacks it, bare "sudo" is FileNotFoundError.
                subprocess.run(["/run/wrappers/bin/sudo", "/run/current-system/sw/bin/systemctl", "restart", "mediamtx"])
            self.send_response(303)
            self.send_header("Location", "/")
            self.end_headers()
            return

        if self.path == "/offline-text":
            length = int(self.headers.get("Content-Length", 0))
            body = parse_qs(self.rfile.read(length).decode())
            text = (body.get("text") or [""])[0].strip()[:MAX_OFFLINE_TEXT_LEN]
            if text:
                OFFLINE_TEXT_FILE.write_text(text)
            else:
                OFFLINE_TEXT_FILE.unlink(missing_ok=True)
            self.send_response(303)
            self.send_header("Location", "/")
            self.end_headers()
            return

        if self.path == "/authcheck":
            length = int(self.headers.get("Content-Length", 0))
            try:
                req = json.loads(self.rfile.read(length) or b"{}")
            except ValueError:
                req = {}
            action = req.get("action")
            allowed = False
            if action == "publish":
                allowed = req.get("ip") in ("127.0.0.1", "::1")
            elif action == "read":
                query = parse_qs(req.get("query") or "")
                given_token = (query.get("preview") or [None])[0]
                allowed = is_live() or (given_token == preview_token())
            self.send_response(200 if allowed else 401)
            self.end_headers()
            return

        self.send_response(404)
        self.end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
