#!/usr/bin/env python3
"""Status page for the Rekordbox export: is the DJ folder ready to copy to a stick?"""

import argparse
import base64
import hashlib
import html
import json
import re
import subprocess
import threading
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from collections import deque
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

RUNNING_STATES = {"activating", "active", "reloading", "deactivating"}
FAST_POLL_STATES = {"exporting", "scanning", "sending"}
SNAPSHOT_TTL = 1.5
RATE_WINDOW = 300.0
MIN_RATE_SPAN = 60.0


def unix_timestamp(value: str | None) -> float | None:
    if not value or not value.startswith("@"):
        return None
    try:
        return float(value[1:]) or None
    except ValueError:
        return None


def syncthing_timestamp(value: str | None) -> float | None:
    if not value:
        return None
    value = re.sub(r"(\.\d{6})\d+", r"\1", value).replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    return parsed.timestamp() if parsed.year > 2000 else None


def iso(timestamp: float | None) -> str | None:
    if not timestamp:
        return None
    return datetime.fromtimestamp(timestamp, timezone.utc).isoformat()


def clock(timestamp: float | None, fallback: str) -> str:
    if not timestamp:
        return fallback
    return time.strftime("%a %d %b, %H:%M", time.localtime(timestamp))


def human_bytes(size: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1000:
            return f"{size:.0f} {unit}" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1000
    return f"{size:.1f} TB"


def plural(count: int, word: str) -> str:
    return f"{count:,} {word}{'' if count == 1 else 's'}"


def systemd_properties(unit: str, *names: str) -> dict[str, str]:
    try:
        output = subprocess.run(
            ["systemctl", "show", unit, "--timestamp=unix"]
            + [f"--property={name}" for name in names],
            capture_output=True,
            text=True,
            timeout=5,
        ).stdout
    except (OSError, subprocess.TimeoutExpired):
        return {}
    return dict(line.split("=", 1) for line in output.splitlines() if "=" in line)


def next_timer_elapse(timer: str) -> float | None:
    try:
        output = subprocess.run(
            ["systemctl", "list-timers", "--all", "--output=json", timer],
            capture_output=True,
            text=True,
            timeout=5,
        ).stdout
        entries = json.loads(output or "[]")
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return None
    next_usec = entries[0].get("next") if entries else None
    return next_usec / 1e6 if next_usec else None


class RemainingTimeEstimator:
    """Recent export speed; unchanged tracks are near-instant, so the overall average misleads."""

    def __init__(self) -> None:
        self.started: float | None = None
        self.samples: deque[tuple[float, int]] = deque()

    def estimate(self, progress: dict) -> float | None:
        if progress.get("phase") != "exporting":
            return None
        started, updated = progress.get("started"), progress.get("updated")
        processed = int(progress.get("processed") or 0)
        remaining = int(progress.get("total") or 0) - processed
        if not started or not updated:
            return None
        if started != self.started:
            self.started = started
            self.samples.clear()
        if not self.samples or self.samples[-1] != (updated, processed):
            self.samples.append((updated, processed))
        while len(self.samples) > 2 and updated - self.samples[1][0] >= RATE_WINDOW:
            self.samples.popleft()

        oldest_time, oldest_processed = self.samples[0]
        done, elapsed = processed - oldest_processed, updated - oldest_time
        if elapsed < MIN_RATE_SPAN or done <= 0:
            return None
        return remaining * elapsed / done


def remaining_text(seconds: float | None, phase: str | None) -> str:
    if phase == "scanning":
        return "Looking for new tracks"
    if phase == "finishing":
        return "Finishing up"
    if seconds is None:
        return "Estimating time left"
    minutes = round(seconds / 60)
    if minutes < 1:
        return "Less than a minute left"
    if minutes < 60:
        return f"About {minutes} min left"
    return f"About {minutes // 60} h {minutes % 60} min left"


class Syncthing:
    def __init__(self, url: str, config_path: Path) -> None:
        self.url = url.rstrip("/")
        self.config_path = config_path

    def api_key(self) -> str:
        key = ET.parse(self.config_path).findtext("gui/apikey")
        if not key:
            raise ValueError(f"no API key in {self.config_path}")
        return key

    def get(self, path: str, **query: str) -> dict:
        url = f"{self.url}{path}"
        if query:
            url += "?" + urllib.parse.urlencode(query)
        request = urllib.request.Request(url, headers={"X-API-Key": self.api_key()})
        with urllib.request.urlopen(request, timeout=3) as response:
            return json.load(response)


def collect(
    options: argparse.Namespace,
    syncthing: Syncthing,
    estimator: RemainingTimeEstimator,
) -> dict:
    unit = systemd_properties(
        options.unit,
        "ActiveState",
        "Result",
        "ExecMainStatus",
        "ExecMainStartTimestamp",
        "ExecMainExitTimestamp",
    )
    timer = {"next": next_timer_elapse(options.timer)}
    try:
        progress = json.loads(Path(options.progress_file).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        progress = {}

    folders = [options.library_folder, options.export_folder]
    try:
        statuses = [syncthing.get("/rest/db/status", folder=f) for f in folders]
        completions = [
            syncthing.get("/rest/db/completion", folder=f, device=options.device)
            for f in folders
        ]
        export_stats = syncthing.get("/rest/stats/folder").get(options.export_folder, {})
        connection = (
            syncthing.get("/rest/system/connections")
            .get("connections", {})
            .get(options.device, {})
        )
        device_stats = syncthing.get("/rest/stats/device").get(options.device, {})
        busy = [status.get("state", "unknown") for status in statuses]
        sync = {
            "state": next((state for state in busy if state != "idle"), "idle"),
            "error": "; ".join(
                f"{f}: {status['error']}"
                for f, status in zip(folders, statuses)
                if status.get("error")
            ),
            "last_scan": syncthing_timestamp(export_stats.get("lastScan")),
            "completion": min(float(c.get("completion", 0)) for c in completions),
            "need_bytes": sum(int(c.get("needBytes", 0)) for c in completions),
            "need_items": sum(
                int(c.get("needItems", 0)) + int(c.get("needDeletes", 0))
                for c in completions
            ),
            "remote_state": next(
                (
                    c.get("remoteState")
                    for c in completions
                    if c.get("remoteState", "valid") != "valid"
                ),
                "valid",
            ),
            "connected": bool(connection.get("connected")),
            "last_seen": syncthing_timestamp(device_stats.get("lastSeen")),
        }
    except (OSError, ValueError, ET.ParseError) as exc:
        sync = {"unreachable": str(exc)}

    return {
        "unit": unit,
        "timer": timer,
        "progress": progress,
        "remaining": estimator.estimate(progress),
        "sync": sync,
    }


def verdict(snapshot: dict) -> tuple[str, str, str]:
    unit, progress, sync = snapshot["unit"], snapshot["progress"], snapshot["sync"]
    finished = progress.get("finished")

    if unit.get("ActiveState") in RUNNING_STATES:
        total = int(progress.get("total") or 0)
        processed = int(progress.get("processed") or 0)
        phase = progress.get("phase", "starting")
        if phase == "exporting" and total:
            detail = f"Checking track {processed:,} of {total:,}."
        elif phase == "scanning":
            detail = "Looking for new and changed tracks."
        else:
            detail = "Updating the databases and playlists."
        return "exporting", "Export running", detail
    if unit.get("Result", "success") != "success" or unit.get("ExecMainStatus", "0") != "0":
        return (
            "failed",
            "Last export failed",
            f"Exit status {unit.get('ExecMainStatus', '?')}. "
            "Check journalctl -u dj-rekordbox.",
        )
    if not progress:
        return "unknown", "No export yet", "The first export has not run yet."
    if progress.get("phase") != "done":
        return "failed", "Last export was interrupted", "The next export will resume it."
    if "unreachable" in sync:
        return "unknown", "Syncthing unreachable", sync["unreachable"]
    if sync["error"]:
        return "failed", "Syncthing folder error", sync["error"]
    if sync["state"] != "idle" or not sync["last_scan"] or sync["last_scan"] < finished:
        return (
            "scanning",
            "Syncthing is picking up the export",
            "It has to scan the folder before it can send the changes.",
        )
    if not sync["connected"]:
        return (
            "offline",
            "Laptop offline",
            "The export is done. Turn on the laptop so Syncthing can send it.",
        )
    if sync["remote_state"] == "paused":
        return (
            "offline",
            "Folder paused on the laptop",
            "Resume dj-library and dj-rekordbox in Syncthing.",
        )
    if sync["remote_state"] == "notSharing":
        return (
            "offline",
            "Laptop is missing a folder",
            "Rebuild the laptop so Syncthing shares dj-library and dj-rekordbox.",
        )
    if sync["completion"] < 100 or sync["need_bytes"] or sync["need_items"]:
        return (
            "sending",
            "Sending to the laptop",
            f"{human_bytes(sync['need_bytes'])} in "
            f"{plural(sync['need_items'], 'file')} left "
            f"({sync['completion']:.0f} %).",
        )
    return (
        "ready",
        "Ready to copy",
        "The laptop has the full export. Plug in the FIESTA stick to copy it.",
    )


def build_view(snapshot: dict) -> dict:
    unit, timer = snapshot["unit"], snapshot["timer"]
    progress, sync = snapshot["progress"], snapshot["sync"]
    state, title, detail = verdict(snapshot)
    counts = progress.get("counts") or {}
    total = int(progress.get("total") or 0)
    processed = int(progress.get("processed") or 0)

    if state == "exporting":
        export_state = "Running"
    elif unit.get("Result", "success") != "success":
        export_state = "Failed"
    else:
        export_state = "Idle"

    tracks = progress.get("tracks")
    library = (
        f"{plural(int(tracks), 'track')}, export.pdb {progress.get('pdb', '?')}"
        if tracks is not None
        else "Not known yet"
    )
    summary = (
        f"{counts.get('added', 0):,} added, {counts.get('updated', 0):,} updated, "
        f"{counts.get('removed', 0):,} removed, {counts.get('failed', 0):,} failed"
        if counts
        else "Nothing yet"
    )

    if "unreachable" in sync:
        folder_state = "Unreachable"
        laptop_state = "Unknown"
        laptop_need = "Unknown"
    else:
        folder_state = sync["state"].capitalize()
        laptop_state = "Connected" if sync["connected"] else "Offline"
        laptop_need = (
            "Has everything"
            if sync["completion"] >= 100 and not sync["need_items"]
            else f"{human_bytes(sync['need_bytes'])} left, "
            f"{sync['completion']:.0f} % complete"
        )

    started = unix_timestamp(unit.get("ExecMainStartTimestamp"))
    finished = progress.get("finished")
    next_run = timer.get("next")
    last_scan = sync.get("last_scan")
    last_seen = sync.get("last_seen")

    return {
        "state": state,
        "fast": state in FAST_POLL_STATES,
        "progress": {
            "hidden": state != "exporting",
            "value": processed,
            "max": max(total, 1),
        },
        "fields": {
            "verdict-title": title,
            "verdict-detail": detail,
            "progress-label": f"{processed:,} / {total:,} tracks" if total else "Starting",
            "progress-current": progress.get("current") or "",
            "progress-remaining": remaining_text(
                snapshot["remaining"], progress.get("phase")
            ),
            "export-state": export_state,
            "export-summary": summary,
            "export-library": library,
            "sync-folder": folder_state,
            "laptop-state": laptop_state,
            "laptop-need": laptop_need,
        },
        "times": {
            "export-started": [iso(started), clock(started, "Never")],
            "export-finished": [iso(finished), clock(finished, "Never")],
            "export-next": [iso(next_run), clock(next_run, "Not scheduled")],
            "sync-scan": [iso(last_scan), clock(last_scan, "Never")],
            "laptop-seen": [iso(last_seen), clock(last_seen, "Never")],
        },
    }


def render(template: str, view: dict) -> str:
    values = {key: html.escape(text) for key, text in view["fields"].items()}
    for key, (timestamp, text) in view["times"].items():
        values[key] = html.escape(text)
        values[f"{key}@"] = html.escape(timestamp or "")
    progress = view["progress"]
    values["state"] = view["state"]
    values["progress-hidden"] = "hidden" if progress["hidden"] else ""
    values["progress-value"] = str(progress["value"])
    values["progress-max"] = str(progress["max"])
    return re.sub(r"\{\{([\w@-]+)\}\}", lambda m: values.get(m.group(1), ""), template)


def content_security_policy(template: str) -> str:
    def hashes(tag: str) -> str:
        return " ".join(
            "'sha256-"
            + base64.b64encode(hashlib.sha256(body.encode()).digest()).decode()
            + "'"
            for body in re.findall(rf"<{tag}>(.*?)</{tag}>", template, re.S)
        )

    return (
        "default-src 'none'; connect-src 'self'; img-src data:; "
        f"style-src {hashes('style')}; script-src {hashes('script')}; "
        "base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
    )


def serve(options: argparse.Namespace) -> None:
    template = Path(options.template).read_text(encoding="utf-8")
    policy = content_security_policy(template)
    syncthing = Syncthing(options.syncthing_url, Path(options.syncthing_config))
    lock = threading.Lock()
    estimator = RemainingTimeEstimator()
    cache: dict = {"at": 0.0, "view": None}

    def current_view() -> dict:
        with lock:
            if cache["view"] is None or time.monotonic() - cache["at"] > SNAPSHOT_TTL:
                cache["view"] = build_view(collect(options, syncthing, estimator))
                cache["at"] = time.monotonic()
            return cache["view"]

    class Handler(BaseHTTPRequestHandler):
        def send(self, status: int, content_type: str, body: bytes) -> None:
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Referrer-Policy", "no-referrer")
            if content_type.startswith("text/html"):
                self.send_header("Content-Security-Policy", policy)
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self) -> None:
            path = urllib.parse.urlsplit(self.path).path
            if path == "/":
                body = render(template, current_view()).encode("utf-8")
                self.send(200, "text/html; charset=utf-8", body)
            elif path == "/api/status":
                body = json.dumps(current_view()).encode("utf-8")
                self.send(200, "application/json", body)
            else:
                self.send(404, "text/plain; charset=utf-8", b"Not found\n")

        def log_message(self, *args) -> None:
            pass

    ThreadingHTTPServer(("127.0.0.1", options.port), Handler).serve_forever()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--template", required=True)
    parser.add_argument("--progress-file", required=True)
    parser.add_argument("--unit", default="dj-rekordbox.service")
    parser.add_argument("--timer", default="dj-rekordbox.timer")
    parser.add_argument("--syncthing-url", default="http://127.0.0.1:8384")
    parser.add_argument("--syncthing-config", required=True)
    parser.add_argument("--library-folder", default="dj-library")
    parser.add_argument("--export-folder", default="dj-rekordbox")
    parser.add_argument("--device", required=True, help="laptop Syncthing device ID")
    serve(parser.parse_args())


if __name__ == "__main__":
    main()
