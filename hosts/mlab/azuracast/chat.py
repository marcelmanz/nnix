"""Live chat for the public radio page (nginx SSE location + systemd service; see proxy.nix and
default.nix). No accounts: GET /chat/events assigns a random name via a cookie on first connect
(kept for the browser session, forgeable client-side like the name itself - there's nothing to
protect), then streams a short backlog plus every new message as Server-Sent Events. POST
/chat/send broadcasts a message to all connected clients. History and the live-text override are
mirrored to a JSON file in STATE_DIRECTORY (see default.nix's StateDirectory) and reloaded on
start, so a deploy/restart doesn't wipe the chat - live clients (connections, per-IP throttle) are
still dropped, that part really is ephemeral.

The owner is recognized by Authelia session, not IP: any request carrying a valid
authelia_session cookie (shared across *.marcel.cool, so logging into any protected subdomain is
enough) is verified against Authelia's /api/verify - no IP to keep in sync across networks. The
owner can also drive the on-air title from chat with "!t <text>" (or bare "!t" to clear it back
to the streamer name); this both broadcasts a "livetext" SSE event and posts a regular
"Track Name: <text>" chat message so the change shows up in the chat log too.

ponytail: run via python3, not shebang
"""

import json
import os
import queue
import random
import re
import sys
import threading
import time
import urllib.error
import urllib.request
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PORT = int(sys.argv[1])
COOKIE_NAME = "chat_name"
COOKIE_RE = re.compile(rf"{COOKIE_NAME}=([^;]+)")
HISTORY_LEN = 50
MAX_MESSAGE_LEN = 300
THROTTLE_S = 1.5
STATE_FILE = Path(os.environ.get("STATE_DIRECTORY", "/var/lib/azuracast-chat")) / "state.json"

OWNER_NAME = "Marcelus Wallace"
# Authelia's forward-auth verify endpoint and a domain from its access_control rules (authelia.nix)
# to check the session against - any admins-group domain works, this doesn't grant access to it.
AUTH_VERIFY_URL = os.environ["AUTH_VERIFY_URL"]
AUTH_CHECK_DOMAIN = os.environ.get("AUTH_CHECK_DOMAIN", "home.marcel.cool")

ADJECTIVES = [
    "Sneaky", "Groovy", "Chill", "Rowdy", "Fuzzy", "Cosmic", "Sleepy", "Jazzy",
    "Feral", "Loyal", "Spicy", "Gloomy", "Silent", "Turbo", "Rusty", "Velvet",
]
ANIMALS = [
    "Otter", "Raccoon", "Falcon", "Panther", "Koala", "Ferret", "Weasel", "Heron",
    "Badger", "Lynx", "Gecko", "Moth", "Pigeon", "Marmot", "Newt", "Toad",
]

history = deque(maxlen=HISTORY_LEN)
history_lock = threading.Lock()
clients = set()
clients_lock = threading.Lock()
throttle = {}
throttle_lock = threading.Lock()
live_text = ""
live_text_lock = threading.Lock()


def is_owner(cookie_header, client_ip):
    if "authelia_session" not in cookie_header:
        return False
    req = urllib.request.Request(
        AUTH_VERIFY_URL,
        headers={
            "Cookie": cookie_header,
            "X-Original-URL": f"https://{AUTH_CHECK_DOMAIN}/",
            "X-Forwarded-Method": "GET",
            "X-Forwarded-Proto": "https",
            "X-Forwarded-Host": AUTH_CHECK_DOMAIN,
            "X-Forwarded-Uri": "/",
            "X-Forwarded-For": client_ip,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=2) as r:
            return r.status == 200
    except (urllib.error.HTTPError, OSError):
        return False


def send_to_clients(event, data):
    with clients_lock:
        dead = []
        for q in clients:
            try:
                q.put_nowait((event, data))
            except queue.Full:
                dead.append(q)
        for q in dead:
            clients.discard(q)


def random_name():
    return f"{random.choice(ADJECTIVES)} {random.choice(ANIMALS)}{random.randint(10, 99)}"


def save_state():
    with history_lock, live_text_lock:
        data = {"history": list(history), "live_text": live_text}
    try:
        STATE_FILE.write_text(json.dumps(data))
    except OSError:
        pass


def load_state():
    global live_text
    try:
        data = json.loads(STATE_FILE.read_text())
    except (OSError, ValueError):
        return
    history.extend(data.get("history", []))
    live_text = data.get("live_text", "")


def broadcast(msg):
    with history_lock:
        history.append(msg)
    save_state()
    send_to_clients("message", msg)


def set_live_text(text):
    global live_text
    with live_text_lock:
        live_text = text
    save_state()
    send_to_clients("livetext", {"text": text})


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def client_ip(self):
        xff = self.headers.get("X-Forwarded-For", "")
        return xff.split(",")[0].strip() or self.client_address[0]

    def client_name(self):
        if is_owner(self.headers.get("Cookie", ""), self.client_ip()):
            self.new_cookie = False
            return OWNER_NAME
        m = COOKIE_RE.search(self.headers.get("Cookie", ""))
        if m:
            self.new_cookie = False
            return m.group(1)
        self.new_cookie = True
        return random_name()

    def write_event(self, event, data):
        self.wfile.write(f"event: {event}\ndata: {json.dumps(data)}\n\n".encode())
        self.wfile.flush()

    def do_GET(self):
        if self.path.split("?")[0] != "/chat/events":
            self.send_response(404)
            self.end_headers()
            return
        name = self.client_name()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "keep-alive")
        if self.new_cookie:
            self.send_header(
                "Set-Cookie", f"{COOKIE_NAME}={name}; Path=/; Max-Age=31536000; SameSite=Lax"
            )
        self.end_headers()

        q = queue.Queue(maxsize=200)
        with clients_lock:
            clients.add(q)
        try:
            self.write_event("name", {"name": name})
            with live_text_lock:
                text = live_text
            if text:
                self.write_event("livetext", {"text": text})
            with history_lock:
                backlog = list(history)
            for msg in backlog:
                self.write_event("message", msg)
            while True:
                try:
                    event, data = q.get(timeout=15)
                    self.write_event(event, data)
                except queue.Empty:
                    self.wfile.write(b": ping\n\n")
                    self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            with clients_lock:
                clients.discard(q)

    def do_POST(self):
        if self.path.split("?")[0] != "/chat/send":
            self.send_response(404)
            self.end_headers()
            return
        name = self.client_name()
        if self.new_cookie:
            # never connected to /chat/events first - no name to post under
            self.send_response(400)
            self.end_headers()
            return
        length = int(self.headers.get("Content-Length", 0))
        if length > 2000:
            self.send_response(413)
            self.end_headers()
            return
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            body = {}
        text = str(body.get("message", "")).strip()[:MAX_MESSAGE_LEN]
        if not text:
            self.send_response(400)
            self.end_headers()
            return

        if name == OWNER_NAME and (text == "!t" or text.startswith("!t ")):
            new_text = text[2:].strip()
            set_live_text(new_text)
            broadcast({"name": name, "text": f"Track Name: {new_text or 'cleared'}", "ts": time.time()})
            self.send_response(204)
            self.end_headers()
            return

        ip = self.client_ip()
        now = time.time()
        with throttle_lock:
            if now - throttle.get(ip, 0) < THROTTLE_S:
                self.send_response(429)
                self.end_headers()
                return
            throttle[ip] = now

        broadcast({"name": name, "text": text, "ts": now})
        self.send_response(204)
        self.end_headers()


class Server(ThreadingHTTPServer):
    daemon_threads = True


load_state()
Server(("127.0.0.1", PORT), Handler).serve_forever()
