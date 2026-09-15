"""Listen-time endpoint for the radio page (systemd socket + nginx location; see azuracast.nix
and the "= /listen-time" location in proxy.nix).

Per-visitor all-time total, keyed by an opaque id the client generates and persists in
localStorage (see public.js) - NOT by IP. This used to sum per-IP rows from AzuraCast's own
`listener` table, but IPv6 privacy-extension addresses rotate several times a day (verified live:
the same visitor showed up under 4 different addresses in a day), which fragmented the total -
each rotation restarted the count from zero. "Current session" needs no server round-trip at all
(the client already knows when its own <audio> started playing), so this only tracks the total.

GET /listen-time?vid=<id>                  -> {"total": <all-time secs>}, no side effect.
GET /listen-time?vid=<id>&heartbeat=<secs> -> same, plus adds <secs> (clamped) to the total -
sent every ~20s while the stream is actually playing (see public.js).

ponytail: run via python3, not shebang
"""

import json
import os
import re
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

LISTEN_PORT = int(sys.argv[1])
VID_RE = re.compile(r"^[A-Za-z0-9_-]{8,64}$")
MAX_HEARTBEAT_S = 90  # client sends ~20s; guards against a spoofed/clock-skewed value
# ponytail: crude cap - evicts the oldest-inserted vid (not true LRU) once over the limit, just
# to bound the file's size against unbounded id churn. Raise DB-backed if this ever matters.
MAX_VIDS = 20000
DATA_FILE = Path(os.environ.get("STATE_DIRECTORY", "/var/lib/azuracast-listen-time")) / "totals.json"

lock = threading.Lock()
try:
    totals = json.loads(DATA_FILE.read_text())
except (OSError, ValueError):
    totals = {}


def save():
    tmp = DATA_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(totals))
    tmp.replace(DATA_FILE)


class H(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # keep the journal quiet

    def send(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        parts = urlsplit(self.path)
        if parts.path != "/listen-time":
            return self.send(404, {})
        qs = parse_qs(parts.query)
        vid = (qs.get("vid") or [""])[0]
        if not VID_RE.match(vid):
            return self.send(400, {})
        heartbeat = (qs.get("heartbeat") or [None])[0]
        with lock:
            if heartbeat is not None:
                try:
                    secs = max(0, min(MAX_HEARTBEAT_S, int(heartbeat)))
                except ValueError:
                    secs = 0
                if secs:
                    if vid not in totals and len(totals) >= MAX_VIDS:
                        totals.pop(next(iter(totals)), None)
                    totals[vid] = totals.get(vid, 0) + secs
                    save()
            total = totals.get(vid, 0)
        self.send(200, {"total": total})


ThreadingHTTPServer(("127.0.0.1", LISTEN_PORT), H).serve_forever()
