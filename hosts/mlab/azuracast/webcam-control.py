#!/usr/bin/env python3
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
TEXT_MODE_FILE = STATE_FILE.parent / "text-mode"
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


def is_live() -> bool:
    return STATE_FILE.exists()


def text_mode_on() -> bool:
    return TEXT_MODE_FILE.exists()


# What the public page/reads actually see: is_live() can stay on while the camera keeps
# recording, but text-mode substitutes the offline text for the video without touching it.
def public_live() -> bool:
    return is_live() and not text_mode_on()


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
    def do_GET(self):
        # Everything the merged live.marcel.cool page needs to render the webcam controls,
        # so EFFECTS and the state-file semantics stay defined here only. Not the same as
        # /status: that one is proxied to the public page, this one is loopback-only (nginx
        # maps exactly "= /webcam-status" to /status and nothing else on this port).
        if self.path == "/state":
            body = json.dumps(
                {
                    "live": is_live(),
                    "text_mode": text_mode_on(),
                    "effect": current_effect(),
                    "effects": list(EFFECTS),
                    "offline_text": OFFLINE_TEXT_FILE.read_text().strip()
                    if OFFLINE_TEXT_FILE.exists()
                    else "",
                    "default_offline_text": DEFAULT_OFFLINE_TEXT,
                    "max_offline_text_len": MAX_OFFLINE_TEXT_LEN,
                    "whep_url": f"https://radio.marcel.cool{WHEP_PATH}?preview={preview_token()}",
                }
            ).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
            return

        if self.path == "/status":
            body = json.dumps({"live": public_live(), "offline_text": current_offline_text()}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
            return

        # No UI lives here any more - live.marcel.cool renders the controls from /state and
        # posts back through nginx's /cam/ route. This process is state, auth and actions.
        self.send_response(404)
        self.end_headers()

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
                # Kills only the runOnInit publisher - runOnInitRestart respawns it with the
                # new filter. Restarting all of mediamtx worked too but took every viewer and
                # the WHEP endpoint down with it. Matched on the camera id because the script
                # execs ffmpeg (its own name is gone) and nothing else opens the BRIO; the
                # rtsp URL would be equally unique but its ":" needs escaping in sudoers.
                # -f matches any command line containing the id, so a shell command that
                # merely mentions it gets killed too. Narrowing by user isn't possible:
                # mediamtx runs under DynamicUser, so the publisher's uid is not stable.
                # ponytail: the recorder's RTSP read still ends, so an effect change mid-show
                # splits the recording; avoiding that needs mediamtx's HTTP API.
                # /run/wrappers/bin: service PATH lacks it, bare "sudo" is FileNotFoundError.
                subprocess.run(["/run/wrappers/bin/sudo", "/run/current-system/sw/bin/pkill", "-f", "usb-046d_Logitech_BRIO_F67E04C5"])
            self.send_response(303)
            self.send_header("Location", "/")
            self.end_headers()
            return

        if self.path == "/text-mode":
            if text_mode_on():
                TEXT_MODE_FILE.unlink(missing_ok=True)
            else:
                TEXT_MODE_FILE.touch()
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
                # Loopback alone isn't enough to allow a read: nginx proxies the public WebRTC
                # leg, so every public viewer also arrives as 127.0.0.1. RTSP is never proxied,
                # so loopback+rtsp is only ever azuracast-live-record pulling the show.
                local_rtsp = req.get("protocol") == "rtsp" and req.get("ip") in (
                    "127.0.0.1",
                    "::1",
                )
                allowed = (
                    public_live() or given_token == preview_token() or local_rtsp
                )
                # livemix is the desk monitor (live.nix). It carries no webcam and is not
                # gated on the public toggle: the only nginx location that proxies it is the
                # radio-lan vhost, which binds 192.168.1.140, and mediamtx's own WebRTC
                # listener is loopback - so reaching this path at all means a LAN client.
                if req.get("path") == "livemix":
                    allowed = True
            self.send_response(200 if allowed else 401)
            self.end_headers()
            return

        self.send_response(404)
        self.end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
