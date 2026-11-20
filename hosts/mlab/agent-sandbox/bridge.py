import asyncio
import errno
import json
import os
import re
import shutil
import tempfile
import time
from pathlib import Path

from aiohttp import web

STATE_DIR = Path(os.environ["STATE_DIR"])
PROJECTS_DIR = STATE_DIR / "projects"
SESSIONS_DIR = STATE_DIR / "sessions"
PORT = int(os.environ["PORT"])
CONTAINER = os.environ.get("CONTAINER", "agent")
MIRRORS_DIR = Path(os.environ["MIRRORS_DIR"])
BUNDLES_DIR = STATE_DIR / "bundles"
GIT_USER = os.environ.get("GIT_USER", "dev")
INDEX = Path(__file__).with_name("index.html")
REPO_RE = re.compile(r"^(?:(?:https|ssh)://[A-Za-z0-9][A-Za-z0-9._~:/@%+-]*|[A-Za-z0-9][A-Za-z0-9._-]*@[A-Za-z0-9][A-Za-z0-9.-]*:[A-Za-z0-9._~/%+-]+)$")
SSH_HOSTS_RE = re.compile(r"^https://(github\.com|codeberg\.org|git\.sr\.ht)/(.+?)/?$")
PROJECT_ID_RE = re.compile(r"^[a-z][a-z0-9]*(_[a-z0-9]+)*$")
SUMMARY_LIMIT = 4000
CONTINUE_PROMPT = "You were interrupted. Check the state of the worktree and continue the task where you left off."

projects = {}
sessions = {}
create_lock = asyncio.Lock()


def worktree_path(session_id):
    return f"/workspace/worktrees/{session_id}"


def project_path(project_id):
    return f"/workspace/projects/{project_id}"


def task_instructions(session):
    return (
        f"You are working unattended in a git worktree on branch {session.branch}. "
        "Nobody is watching, so don't ask questions: make reasonable choices and note them. "
        "Commit your work on this branch when done, and end with a short summary of what you did and what is left."
    )


def save_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data))


async def run_in_container(*args):
    proc = await asyncio.create_subprocess_exec(
        "nixos-container", "run", CONTAINER, "--", "runuser", "-l", "agent", "-c", " ".join(map(_quote, args)),
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
    )
    output, _ = await proc.communicate()
    return proc.returncode, output.decode(errors="replace")


async def run_as_git_user(*args):
    proc = await asyncio.create_subprocess_exec(
        "runuser", "-u", GIT_USER, "--", "env", f"HOME=/home/{GIT_USER}", "GIT_TERMINAL_PROMPT=0",
        "GIT_SSH_COMMAND=ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new", *args,
        cwd=MIRRORS_DIR, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
    )
    output, _ = await proc.communicate()
    if proc.returncode != 0:
        raise web.HTTPBadGateway(text=output.decode(errors="replace"))
    return output.decode(errors="replace")


async def read_from_container(*args):
    proc = await asyncio.create_subprocess_exec(
        "nixos-container", "run", CONTAINER, "--", "runuser", "-l", "agent", "-c", " ".join(map(_quote, args)),
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
    )
    output, errors = await proc.communicate()
    if proc.returncode != 0:
        raise web.HTTPBadGateway(text=errors.decode(errors="replace"))
    return output


def mirror_path(project_id):
    return MIRRORS_DIR / f"{project_id}.git"


async def update_mirror(project_id):
    await run_as_git_user("git", "-C", str(mirror_path(project_id)), "fetch", "--quiet", "origin")


async def run_or_fail(*args):
    code, output = await run_in_container(*args)
    if code != 0:
        raise web.HTTPBadGateway(text=output)
    return output


class Session:
    def __init__(self, session_id, project, title, branch, base, created, result=None):
        self.id = session_id
        self.title = title
        self.project = project
        self.branch = branch
        self.base = base
        self.created = created
        self.result = result
        self.log_path = SESSIONS_DIR / f"{session_id}.jsonl"
        self.input_path = SESSIONS_DIR / f"{session_id}.in"
        self.output_path = SESSIONS_DIR / f"{session_id}.out"
        self.cursor_path = SESSIONS_DIR / f"{session_id}.cursor"
        self.unit = f"agent-task-{session_id}.service"
        self.tailer = None
        self.offset = 0
        self.running = False
        self.exited = False
        self.last_text = ""
        self.deleted = False
        self.waiters = set()
        if self.cursor_path.exists():
            cursor = json.loads(self.cursor_path.read_text())
            self.offset, self.running, self.last_text = cursor["offset"], cursor["running"], cursor["last_text"]

    def meta(self):
        return {
            "id": self.id, "project": self.project, "title": self.title, "branch": self.branch, "created": self.created,
            "running": self.running, "alive": self.attached(), "result": self.result,
        }

    def save(self):
        save_json(SESSIONS_DIR / f"{self.id}.json", {
            "id": self.id, "project": self.project, "title": self.title, "branch": self.branch, "base": self.base,
            "created": self.created, "result": self.result,
        })

    def save_cursor(self):
        save_json(self.cursor_path, {"offset": self.offset, "running": self.running, "last_text": self.last_text})

    def append(self, record):
        if self.deleted:
            return
        with self.log_path.open("a") as log:
            log.write(json.dumps(record) + "\n")
        for waiter in self.waiters:
            waiter.set()

    def read_log(self, start):
        if not self.log_path.exists():
            return []
        with self.log_path.open() as log:
            return log.read().splitlines()[start:]

    def attached(self):
        return self.tailer is not None and not self.tailer.done()

    def has_unread_output(self):
        return self.output_path.exists() and self.output_path.stat().st_size > self.offset

    async def unit_active(self):
        proc = await asyncio.create_subprocess_exec("systemctl", "is-active", "--quiet", self.unit)
        return await proc.wait() == 0

    def attach(self):
        if not self.attached():
            self.exited = False
            self.tailer = asyncio.create_task(self.tail())

    async def start(self):
        if await self.unit_active():
            self.attach()
            return
        if not self.input_path.exists():
            os.mkfifo(self.input_path, 0o600)
        inner = " ".join([
            "cd", _quote(worktree_path(self.id)), "&&", "exec", "pi", "--mode", "rpc", "--continue",
            "--session-dir", _quote(f"/workspace/.sessions/{self.id}"),
            "--append-system-prompt", _quote(task_instructions(self)),
        ])
        runner = (
            'exec 3<>"$1"; nixos-container run "$2" -- runuser -l agent -c "$3" <&3 >>"$4" 2>&1; '
            'echo "{\\"type\\": \\"bridge_exit\\", \\"code\\": $?}" >>"$4"'
        )
        proc = await asyncio.create_subprocess_exec(
            "systemd-run", "--quiet", "--collect", f"--unit={self.unit}", f"--setenv=PATH={os.environ['PATH']}",
            "--", shutil.which("sh"), "-c", runner, "agent-task", str(self.input_path), CONTAINER, inner, str(self.output_path),
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
        )
        output, _ = await proc.communicate()
        if proc.returncode != 0:
            raise web.HTTPBadGateway(text=output.decode(errors="replace"))
        self.attach()

    def read_output_line(self, output):
        output.seek(self.offset)
        line = output.readline()
        if not line.endswith(b"\n"):
            return None
        return line

    async def tail(self):
        self.output_path.touch()
        last_check = 0
        with self.output_path.open("rb") as output:
            while not self.deleted:
                line = self.read_output_line(output)
                if line is None:
                    if time.monotonic() - last_check < 2:
                        await asyncio.sleep(0.2)
                        continue
                    last_check = time.monotonic()
                    if await self.unit_active() or (line := self.read_output_line(output)) is not None:
                        continue
                    break
                self.offset += len(line)
                await self.handle(line)
                self.save_cursor()
        if not self.exited and not self.deleted:
            self.running = False
            self.save_cursor()
            self.append({"type": "bridge_exit", "code": None})

    async def handle(self, line):
        try:
            record = json.loads(line)
        except ValueError:
            record = {"type": "bridge_stderr", "text": line.decode(errors="replace")}
        kind = record.get("type")
        if kind == "agent_start":
            self.running = True
            self.result = None
        elif kind == "message_end" and record.get("message", {}).get("role") == "assistant":
            text = "".join(c.get("text", "") for c in record["message"].get("content", []) if c.get("type") == "text")
            if text.strip():
                self.last_text = text
        elif kind == "bridge_exit":
            self.running = False
            self.exited = True
        self.append(record)
        if kind == "agent_settled":
            self.running = False
            await self.finish(aborted=bool(record.get("aborted")))

    async def finish(self, aborted):
        path = worktree_path(self.id)
        _, commits = await run_in_container("git", "-C", path, "log", "--oneline", f"{self.base}..HEAD")
        _, diffstat = await run_in_container("git", "-C", path, "diff", "--stat", self.base)
        _, status = await run_in_container("git", "-C", path, "status", "--short")
        self.result = {
            "aborted": aborted,
            "finished": time.time(),
            "summary": self.last_text[-SUMMARY_LIMIT:],
            "commits": commits.strip(),
            "diffstat": diffstat.strip(),
            "uncommitted": status.strip(),
        }
        self.save()
        self.append({"type": "session_result", **self.result})

    async def send(self, command):
        await self.start()
        data = json.dumps(command).encode() + b"\n"
        for _ in range(50):
            try:
                fd = os.open(self.input_path, os.O_WRONLY | os.O_NONBLOCK)
                break
            except OSError as error:
                if error.errno != errno.ENXIO:
                    raise
                await asyncio.sleep(0.1)
        else:
            raise web.HTTPBadGateway(text="agent did not start reading its input")
        try:
            os.set_blocking(fd, True)
            os.write(fd, data)
        finally:
            os.close(fd)

    async def stop(self):
        proc = await asyncio.create_subprocess_exec("systemctl", "stop", self.unit, stderr=asyncio.subprocess.DEVNULL)
        await proc.wait()


def load_state():
    PROJECTS_DIR.mkdir(parents=True, exist_ok=True)
    SESSIONS_DIR.mkdir(parents=True, exist_ok=True)
    for meta_file in PROJECTS_DIR.glob("*.json"):
        data = json.loads(meta_file.read_text())
        projects[data["id"]] = data
    for meta_file in SESSIONS_DIR.glob("*.json"):
        data = json.loads(meta_file.read_text())
        sessions[data["id"]] = Session(data["id"], data["project"], data["title"], data["branch"], data["base"], data["created"], data.get("result"))


def prefer_ssh(repo):
    match = SSH_HOSTS_RE.match(repo)
    return f"git@{match[1]}:{match[2]}" if match else repo


def same_repo(a, b):
    return a.rstrip("/").removesuffix(".git") == b.rstrip("/").removesuffix(".git")


def project_id_from_repo(repo):
    name = re.split(r"[/:]", repo.rstrip("/"))[-1].removesuffix(".git").lower()
    name = re.sub(r"[^a-z0-9]+", "_", name).strip("_")
    if name and not name[0].isalpha():
        name = "p_" + name
    return name


def find(request):
    session = sessions.get(request.match_info["id"])
    if session is None:
        raise web.HTTPNotFound()
    return session


async def index(request):
    return web.FileResponse(INDEX)


async def page(request):
    if request.match_info["project"] == "api":
        raise web.HTTPNotFound()
    return web.FileResponse(INDEX)


async def list_projects(request):
    return web.json_response(sorted(projects.values(), key=lambda p: p["id"]))


async def create_project(request):
    body = await request.json()
    repo = prefer_ssh(str(body.get("repo") or "").strip())
    if repo and not REPO_RE.match(repo):
        raise web.HTTPBadRequest(text="repo must be an https://, ssh:// or git@host:path url")
    project_id = str(body.get("id") or "").strip() or project_id_from_repo(repo)
    if not PROJECT_ID_RE.match(project_id):
        raise web.HTTPBadRequest(text="project id must look like word or word_x (lowercase letters, digits, underscores)")
    async with create_lock:
        if repo:
            for project in projects.values():
                if same_repo(project["repo"], repo):
                    return web.json_response(project)
        if project_id in projects:
            raise web.HTTPConflict(text=f"project {project_id} already exists for {projects[project_id]['repo'] or 'an empty repo'}")
        path = project_path(project_id)
        if repo:
            mirror = str(mirror_path(project_id))
            await run_as_git_user("git", "clone", "--quiet", "--bare", "--", repo, mirror)
            await run_as_git_user("git", "-C", mirror, "config", "remote.origin.fetch", "+refs/heads/*:refs/heads/*")
            await run_or_fail("git", "clone", "--quiet", "--", f"file:///mirrors/{project_id}.git", path)
        else:
            await run_or_fail("git", "init", "--quiet", path)
            await run_or_fail("git", "-C", path, "commit", "--quiet", "--allow-empty", "-m", "init")
        project = {"id": project_id, "repo": repo, "created": time.time()}
        save_json(PROJECTS_DIR / f"{project_id}.json", project)
        projects[project_id] = project
    return web.json_response(project)


async def list_sessions(request):
    return web.json_response(sorted((s.meta() for s in sessions.values()), key=lambda m: -m["created"]))


def next_session_id(project_id):
    number = 1
    while f"{project_id}_{number}" in sessions:
        number += 1
    return f"{project_id}_{number}"


async def create_session(request):
    project = projects.get(request.match_info["project"])
    if project is None:
        raise web.HTTPNotFound()
    body = await request.json()
    message = str(body.get("message") or "").strip()
    if not message:
        raise web.HTTPBadRequest(text="prompt is required")
    async with create_lock:
        session_id = next_session_id(project["id"])
        branch = f"agent/{session_id}"
        path = project_path(project["id"])
        start_point = "HEAD"
        if project["repo"]:
            await update_mirror(project["id"])
            await run_or_fail("git", "-C", path, "fetch", "--quiet", "origin")
            start_point = "origin/HEAD"
        await run_or_fail("git", "-C", path, "worktree", "add", "--quiet", "-b", branch, worktree_path(session_id), start_point)
        base = (await run_or_fail("git", "-C", worktree_path(session_id), "rev-parse", "HEAD")).strip()
        title = message.splitlines()[0][:80]
        session = Session(session_id, project["id"], title, branch, base, time.time())
        session.save()
        sessions[session_id] = session
    await send_prompt(session, message)
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


async def send_prompt(session, message):
    command = {"type": "prompt", "message": message}
    if session.running:
        command["streamingBehavior"] = "steer"
    session.append({"type": "user_prompt", "message": message, "timestamp": time.time()})
    await session.send(command)


async def prompt(request):
    session = find(request)
    body = await request.json()
    await send_prompt(session, str(body["message"]))
    return web.json_response({"ok": True})


async def resume(request):
    session = find(request)
    if session.running:
        raise web.HTTPConflict(text="task is still working")
    await send_prompt(session, CONTINUE_PROMPT)
    return web.json_response({"ok": True})


async def abort(request):
    session = find(request)
    if await session.unit_active():
        await session.send({"type": "abort"})
    return web.json_response({"ok": True})


async def stop(request):
    session = find(request)
    await session.stop()
    return web.json_response({"ok": True})


async def push(request):
    session = find(request)
    project = projects[session.project]
    if not project["repo"]:
        raise web.HTTPBadRequest(text="this project has no remote to push to")
    await update_mirror(project["id"])
    bundle = await read_from_container(
        "git", "-C", worktree_path(session.id), "bundle", "create", "--quiet", "-", session.branch, "--not", "--remotes=origin",
    )
    mirror = str(mirror_path(project["id"]))
    BUNDLES_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=BUNDLES_DIR, suffix=".bundle") as bundle_file:
        bundle_file.write(bundle)
        bundle_file.flush()
        os.chmod(bundle_file.name, 0o644)
        await run_as_git_user(
            "git", "-c", "fetch.fsckObjects=true", "-C", mirror, "fetch", "--quiet", bundle_file.name,
            f"refs/heads/{session.branch}:refs/heads/{session.branch}",
        )
    output = await run_as_git_user("git", "-C", mirror, "push", "--porcelain", "origin", f"refs/heads/{session.branch}")
    session.append({"type": "bridge_push", "text": output.strip()})
    return web.json_response({"ok": True, "output": output})


async def delete_session(request):
    session = find(request)
    async with create_lock:
        session.deleted = True
        sessions.pop(session.id, None)
        await session.stop()
        if session.tailer is not None:
            session.tailer.cancel()
        path = project_path(session.project)
        await run_in_container("git", "-C", path, "worktree", "remove", "--force", worktree_path(session.id))
        await run_in_container("git", "-C", path, "worktree", "prune")
        await run_in_container("git", "-C", path, "branch", "-D", session.branch)
        if projects[session.project]["repo"]:
            try:
                await run_as_git_user("git", "-C", str(mirror_path(session.project)), "branch", "-D", session.branch)
            except web.HTTPBadGateway:
                pass
        await run_in_container("rm", "-rf", f"/workspace/.sessions/{session.id}")
        (SESSIONS_DIR / f"{session.id}.json").unlink(missing_ok=True)
        for path in (session.log_path, session.input_path, session.output_path, session.cursor_path):
            path.unlink(missing_ok=True)
    return web.json_response({"ok": True})


async def reattach(app):
    for session in sessions.values():
        if session.has_unread_output() or await session.unit_active():
            session.attach()


load_state()
app = web.Application()
app.on_startup.append(reattach)
app.add_routes([
    web.get("/", index),
    web.get("/api/projects", list_projects),
    web.post("/api/projects", create_project),
    web.post("/api/projects/{project}/sessions", create_session),
    web.get("/api/sessions", list_sessions),
    web.get("/api/sessions/{id}/events", events),
    web.post("/api/sessions/{id}/prompt", prompt),
    web.post("/api/sessions/{id}/continue", resume),
    web.post("/api/sessions/{id}/abort", abort),
    web.post("/api/sessions/{id}/stop", stop),
    web.post("/api/sessions/{id}/push", push),
    web.delete("/api/sessions/{id}", delete_session),
    web.get(r"/{project:[a-z][a-z0-9_]*}", page),
    web.get(r"/{project:[a-z][a-z0-9_]*}/{task:[a-z][a-z0-9_]*}", page),
])
web.run_app(app, host="127.0.0.1", port=PORT)
