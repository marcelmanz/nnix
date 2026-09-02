"""Listen-time endpoint for the radio page (systemd socket + nginx location; see azuracast.nix
and the "= /listen-time" location in proxy.nix).

GET /listen-time -> {"current": <secs this session>, "total": <secs all-time>} for the
requester's own IP. The IP comes from X-Forwarded-For / X-Real-IP, exactly what AzuraCast
itself records in listener.listener_ip - so visitors can only ever see what the admin panel
already shows for that IP, and the numbers match what the station reports.

Only the radio nginx vhost (127.0.0.1) can reach this socket, so trusting the forwarded
headers adds no new privilege. Data comes from the AzuraCast DB (one podman exec per request,
same pattern as azuracast-settings); the page polls at most once a minute and a 10s per-IP
throttle keeps that near zero.

ponytail: note - run via python3, not shebang
"""

import json
import os
import re
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LISTEN_PORT = int(sys.argv[1])
IP_RE = re.compile(r"^[0-9A-Fa-f.:]+$")  # dotted-quad or IPv6, nothing else
THROTTLE_S = 10
throttle = {}
throttle_lock = threading.Lock()


def db(sql):
    """Run sql on the AzuraCast DB inside the container (podman exec; one round-trip)."""
    out = subprocess.run(
        [
            "podman",
            "exec",
            "azuracast",
            "mariadb",
            "-N",
            "-B",
            "-u",
            "azuracast",
            "-p" + os.environ["MYSQL_PASSWORD"],
            "azuracast",
            "-e",
            sql,
        ],
        capture_output=True,
        timeout=15,
        check=False,
    )
    if out.returncode != 0:
        raise RuntimeError(out.stderr.decode(errors="replace").strip()[:200])
    current, total = (int(x) for x in out.stdout.split())
    return current, total


class H(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # keep the journal quiet

    def send(self, code, body):
        data = json.dumps(body).encode() if body is not None else b"{}"
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.split("?")[0] != "/listen-time":
            return self.send(404, None)
        xff = self.headers.get("X-Forwarded-For", "")
        ip = xff.split(",")[0].strip() or self.headers.get("X-Real-IP", "")
        if not IP_RE.match(ip):
            return self.send(400, None)
        now = time.time()
        with throttle_lock:
            if len(throttle) > 10000:
                throttle.clear()
            if now - throttle.get(ip, 0) < THROTTLE_S:
                return self.send(429, None)
            throttle[ip] = now
        try:
            # ponytail: direct DB coupling - the AzuraCast HTTP API exposes only aggregate
            # listener counts publicly and needs an (unconfigured) admin key for per-IP rows,
            # with no per-IP all-time total at all. This repo already reads the DB via
            # `podman exec mariadb` in azuracast-settings/autoplaylist, so we follow suit; if a
            # future AzuraCast upgrade renames listener.{listener_ip,timestamp_start/end}, this
            # query is the only thing to fix (the table already changed once: listeners +
            # listener_log merged into listener).
            # one round-trip: current = row(s) with timestamp_end still NULL (live -> NOW());
            # total = every session this IP has ever had. SUM(...) FILTER (...) is MySQL/Postgres
            # syntax that MariaDB rejects, hence the CASE form.
            current, total = db(
                "SELECT COALESCE(SUM(CASE WHEN timestamp_end IS NULL "
                "THEN TIMESTAMPDIFF(SECOND, timestamp_start, NOW()) ELSE 0 END), 0), "
                "COALESCE(SUM(TIMESTAMPDIFF(SECOND, timestamp_start, "
                "COALESCE(timestamp_end, NOW()))), 0) "
                f"FROM listener WHERE listener_ip='{ip}'"
            )
        except Exception:  # noqa: BLE001
            return self.send(500, None)
        self.send(200, {"current": current, "total": total})


ThreadingHTTPServer(("127.0.0.1", LISTEN_PORT), H).serve_forever()
