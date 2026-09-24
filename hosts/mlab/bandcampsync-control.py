#!/usr/bin/env python3
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1])


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == "/sync":
            # --no-block: bandcampsync.service can run for minutes, and systemctl start
            # on a oneshot blocks until it finishes otherwise.
            subprocess.run(
                [
                    "/run/wrappers/bin/sudo",
                    "/run/current-system/sw/bin/systemctl",
                    "start",
                    "--no-block",
                    "bandcampsync.service",
                ]
            )
            body = b"<!doctype html><p>Sync started, check back in a few minutes.</p><p><a href=/>Back</a></p>"
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(404)
        self.end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
