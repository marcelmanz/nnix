#!/usr/bin/env python3
import os
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

UNIT = "azuracast-live-capture"
PORT = int(sys.argv[1])
AMIXER = sys.argv[2]
FFMPEG = sys.argv[3]
SYSTEMCTL = "/run/current-system/sw/bin/systemctl"
SUDO = "/run/wrappers/bin/sudo"
MIC_CONTROL = "Mic Capture Switch"
TEST_SECS = 4
TEST_FILE = Path(os.environ.get("STATE_DIRECTORY", "/var/lib/azuracast-live-web")) / "test-mic.mp3"

PAGE = """<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Live DJ stream</title>
<style>
body {{ font-family: sans-serif; background: #111; color: #eee; display: flex; flex-direction: column;
       align-items: center; justify-content: center; min-height: 100vh; margin: 0; gap: 1.5rem; padding: 1rem; }}
.badge {{ font-size: 1.5rem; padding: 0.5rem 1.5rem; border-radius: 2rem; }}
.live, .on {{ background: #2e7d32; }}
.offline, .off {{ background: #555; }}
button {{ font-size: 1.25rem; padding: 0.8rem 1.6rem; border-radius: 0.5rem; border: none; cursor: pointer; }}
.row {{ display: flex; flex-direction: column; align-items: center; gap: 0.5rem; }}
.err {{ color: #ef9a9a; max-width: 90vw; text-align: center; }}
audio {{ width: min(90vw, 360px); }}
</style></head>
<body>
<div class="row">
  <div class="badge {live_badge}">{live_status}</div>
  <form method="post" action="/toggle"><button>{live_action}</button></form>
</div>
<div class="row">
  <div class="badge {mic_badge}">Mic: {mic_status}</div>
  <form method="post" action="/mic-toggle"><button>{mic_action}</button></form>
</div>
<div class="row">
  <form method="post" action="/test-mic"><button>Test microphone ({test_secs}s)</button></form>
  {test_result}
</div>
</body></html>
"""


def is_active() -> bool:
    return subprocess.run([SYSTEMCTL, "is-active", "--quiet", UNIT]).returncode == 0


def mic_on() -> bool:
    out = subprocess.run(
        [AMIXER, "-c", "Mic", "cget", f"name={MIC_CONTROL}"],
        capture_output=True, text=True, check=False,
    ).stdout
    return "values=on" in out


def set_mic(on: bool):
    subprocess.run(
        [AMIXER, "-c", "Mic", "cset", f"name={MIC_CONTROL}", "on" if on else "off"],
        check=False,
    )


class Handler(BaseHTTPRequestHandler):
    def render(self, test_result=""):
        live = is_active()
        mic = mic_on()
        html = PAGE.format(
            live_badge="live" if live else "offline",
            live_status="LIVE" if live else "OFFLINE",
            live_action="Stop streaming" if live else "Start streaming",
            mic_badge="on" if mic else "off",
            mic_status="ON" if mic else "OFF (muted)",
            mic_action="Mute mic" if mic else "Unmute mic",
            test_secs=TEST_SECS,
            test_result=test_result,
        )
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(html.encode())

    def do_GET(self):
        if self.path.split("?")[0] == "/test-mic.mp3":
            if not TEST_FILE.exists():
                self.send_response(404)
                self.end_headers()
                return
            data = TEST_FILE.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "audio/mpeg")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        self.render()

    def do_POST(self):
        if self.path == "/toggle":
            action = "stop" if is_active() else "start"
            subprocess.run([SUDO, SYSTEMCTL, action, UNIT], check=False)
            self.send_response(303)
            self.send_header("Location", "/")
            self.end_headers()
            return

        if self.path == "/mic-toggle":
            set_mic(not mic_on())
            self.send_response(303)
            self.send_header("Location", "/")
            self.end_headers()
            return

        if self.path == "/test-mic":
            # Opens the raw mic device directly - fails if azuracast-live-mix already has it
            # open (i.e. you're already live), which surfaces as a plain error below rather
            # than fighting over the device.
            proc = subprocess.run(
                [
                    FFMPEG, "-y", "-f", "alsa", "-ar", "44100", "-ac", "1",
                    "-i", "plughw:CARD=Mic", "-t", str(TEST_SECS),
                    "-c:a", "libmp3lame", "-b:a", "128k", str(TEST_FILE),
                ],
                capture_output=True, check=False,
            )
            if proc.returncode == 0:
                result = (
                    '<audio controls autoplay src="/test-mic.mp3?t=' + str(int(time.time())) + '"></audio>'
                )
            else:
                result = '<p class="err">Could not record - is the mic connected, and not already in use by a live broadcast?</p>'
            self.render(test_result=result)
            return

        self.send_response(404)
        self.end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
