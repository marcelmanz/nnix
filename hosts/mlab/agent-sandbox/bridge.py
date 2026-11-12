import asyncio
import json
import os
import re
import secrets
import time
from pathlib import Path

from aiohttp import web

STATE_DIR = Path(os.environ["STATE_DIR"])
PORT = int(os.environ["PORT"])
CONTAINER = os.environ.get("CONTAINER", "agent")
INDEX = Path(__file__).with_name("index.html")
REPO_RE = re.compile(r"^https://[A-Za-z0-9._~:/@%+-]+$")

sessions = {}


class Session:
    def __init__(self, session_id, name, created):
        self.id = session_id
        self.name = name
        self.created = created
        self.log_path = STATE_DIR / f"{session_id}.jsonl"
        self.proc = None
        self.running = False
        self.waiters = set()

    def meta(self):
        return {"id": self.id, "name": self.name, "created": self.created, "running": self.running, "alive": self.proc is not None}

    def append(self, record):
        with self.log_path.open("a") as log:
            log.write(json.dumps(record) + "\n")
        for waiter in self.waiters:
            waiter.set()

    def read_log(self, start):
        if not self.log_path.exists():
            return []
        with self.log_path.open() as log:
            return log.read().splitlines()[start:]

    async def start(self):
        if self.proc is not None:
            return
        inner = f"cd /workspace/{self.id} && exec pi --mode rpc --session-dir /workspace/.sessions/{self.id}"
        self.proc = await asyncio.create_subprocess_exec(
            "nixos-container", "run", CONTAINER, "--", "runuser", "-l", "agent", "-c", inner,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            limit=64 * 1024 * 1024,
        )
        asyncio.create_task(self.pump_stdout(self.proc))
        asyncio.create_task(self.pump_stderr(self.proc))

    async def pump_stdout(self, proc):
        while line := await proc.stdout.readline():
            try:
                record = json.loads(line)
            except ValueError:
                record = {"type": "bridge_stdout", "text": line.decode(errors="replace")}
            kind = record.get("type")
            if kind == "agent_start":
                self.running = True
            elif kind == "agent_settled":
                self.running = False
            self.append(record)
        code = await proc.wait()
        self.running = False
        self.proc = None
        self.append({"type": "bridge_exit", "code": code})

    async def pump_stderr(self, proc):
        while line := await proc.stderr.readline():
            self.append({"type": "bridge_stderr", "text": line.decode(errors="replace")})

    async def send(self, command):
        await self.start()
        self.proc.stdin.write(json.dumps(command).encode() + b"\n")
        await self.proc.stdin.drain()


def load_sessions():
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    for meta_file in STATE_DIR.glob("*.meta.json"):
        data = json.loads(meta_file.read_text())
        sessions[data["id"]] = Session(data["id"], data["name"], data["created"])


def find(request):
    session = sessions.get(request.match_info["id"])
    if session is None:
        raise web.HTTPNotFound()
    return session


async def index(request):
    return web.FileResponse(INDEX)


async def list_sessions(request):
    return web.json_response(sorted((s.meta() for s in sessions.values()), key=lambda m: -m["created"]))


async def create_session(request):
    body = await request.json()
    name = str(body.get("name") or "session")[:80]
    repo = str(body.get("repo") or "").strip()
    if repo and not REPO_RE.match(repo):
        raise web.HTTPBadRequest(text="repo must be an https url")
    session_id = secrets.token_hex(6)
    clone = ["git", "clone", "--", repo, f"/workspace/{session_id}"] if repo else ["mkdir", f"/workspace/{session_id}"]
    proc = await asyncio.create_subprocess_exec(
        "nixos-container", "run", CONTAINER, "--", "runuser", "-l", "agent", "-c", " ".join(map(_quote, clone)),
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
    )
    output, _ = await proc.communicate()
    if proc.returncode != 0:
        raise web.HTTPBadGateway(text=output.decode(errors="replace"))
    session = Session(session_id, name, time.time())
    (STATE_DIR / f"{session_id}.meta.json").write_text(json.dumps({"id": session_id, "name": name, "created": session.created}))
    sessions[session_id] = session
    return web.json_response(session.meta())


def _quote(arg):
    return "'" + arg.replace("'", "'\\''") + "'"


async def events(request):
    session = find(request)
    response = web.StreamResponse(headers={"Content-Type": "text/event-stream", "Cache-Control": "no-cache", "X-Accel-Buffering": "no"})
    await response.prepare(request)
    cursor = int(request.headers.get("Last-Event-ID", "-1")) + 1
    waiter = asyncio.Event()
    session.waiters.add(waiter)
    try:
        while True:
            waiter.clear()
            for line in session.read_log(cursor):
                await response.write(f"id: {cursor}\ndata: {line}\n\n".encode())
                cursor += 1
            try:
                await asyncio.wait_for(waiter.wait(), timeout=15)
            except asyncio.TimeoutError:
                await response.write(b": keepalive\n\n")
    except (ConnectionResetError, asyncio.CancelledError):
        pass
    finally:
        session.waiters.discard(waiter)
    return response


async def prompt(request):
    session = find(request)
    body = await request.json()
    command = {"type": "prompt", "message": str(body["message"])}
    if session.running:
        command["streamingBehavior"] = "steer"
    session.append({"type": "user_prompt", "message": command["message"], "timestamp": time.time()})
    await session.send(command)
    return web.json_response({"ok": True})


async def abort(request):
    session = find(request)
    if session.proc is not None:
        await session.send({"type": "abort"})
    return web.json_response({"ok": True})


async def stop(request):
    session = find(request)
    if session.proc is not None:
        session.proc.stdin.close()
    return web.json_response({"ok": True})


async def shutdown(app):
    for session in sessions.values():
        if session.proc is not None:
            session.proc.terminate()


load_sessions()
app = web.Application()
app.on_shutdown.append(shutdown)
app.add_routes([
    web.get("/", index),
    web.get("/api/sessions", list_sessions),
    web.post("/api/sessions", create_session),
    web.get("/api/sessions/{id}/events", events),
    web.post("/api/sessions/{id}/prompt", prompt),
    web.post("/api/sessions/{id}/abort", abort),
    web.post("/api/sessions/{id}/stop", stop),
])
web.run_app(app, host="127.0.0.1", port=PORT)
