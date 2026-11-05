#!/usr/bin/env python3
import fcntl
import html
import json
import os
import re
import sqlite3
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STATE_DIR = os.environ.get("STATE_DIRECTORY", "/var/lib/tiktok-follow")
DB_PATH = os.path.join(STATE_DIR, "follow.db")
LOCK_PATH = os.path.join(STATE_DIR, "check.lock")
OFFTIKTOK_API_URL = os.environ["OFFTIKTOK_API_URL"]
OFFTIKTOK_URL = os.environ["OFFTIKTOK_URL"]
OFFTIKTOK_PUBLIC_API_URL = os.environ["OFFTIKTOK_PUBLIC_API_URL"]

BACKFILL_COUNT = 10
FIRST_LIST_COUNT = 30
DAILY_LIST_COUNT = 20
MIN_VIDEO_BYTES = 50_000
HANDLE_RE = re.compile(r"^[A-Za-z0-9._]{1,30}$")


def db():
    conn = sqlite3.connect(DB_PATH, timeout=30)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    with db() as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS profiles (
                handle TEXT PRIMARY KEY,
                added_at INTEGER NOT NULL,
                last_checked INTEGER,
                last_error TEXT
            );
            CREATE TABLE IF NOT EXISTS videos (
                tiktok_id TEXT PRIMARY KEY,
                handle TEXT NOT NULL,
                title TEXT,
                upload_date TEXT,
                status TEXT NOT NULL,
                post_id INTEGER,
                error TEXT,
                seen_at INTEGER NOT NULL
            );
            """
        )


def parse_handle(text):
    text = text.strip()
    match = re.search(r"tiktok\.com/@([^/?#]+)", text)
    handle = (match.group(1) if match else text).lstrip("@")
    return handle if HANDLE_RE.match(handle) else None


def list_profile_videos(handle, count):
    result = subprocess.run(
        [
            "yt-dlp",
            "--flat-playlist",
            "--no-cache-dir",
            "--no-warnings",
            "--playlist-end",
            str(count),
            "--print",
            "%(.{id,upload_date,title})j",
            f"https://www.tiktok.com/@{handle}",
        ],
        capture_output=True,
        text=True,
        timeout=300,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip().splitlines()[-1] if result.stderr.strip() else "yt-dlp failed")
    return [json.loads(line) for line in result.stdout.splitlines() if line.strip()]


def video_size(mp4_url):
    request = urllib.request.Request(OFFTIKTOK_API_URL + mp4_url, method="HEAD")
    with urllib.request.urlopen(request, timeout=30) as response:
        return int(response.headers.get("Content-Length") or 0)


def fetch_into_offtiktok(tiktok_url):
    api_url = f"{OFFTIKTOK_API_URL}/by_url/{urllib.parse.quote(tiktok_url, safe='')}"
    try:
        with urllib.request.urlopen(api_url, timeout=600) as response:
            post = json.load(response)
    except urllib.error.HTTPError as error:
        body = error.read().decode(errors="replace")
        try:
            message = json.loads(body).get("error", body)
        except ValueError:
            message = body
        return "failed", None, f"offtiktok {error.code}: {message}"[:300], {}
    except Exception as error:
        return "failed", None, str(error)[:300], {}

    post_id = post.get("id")
    mp4_url = (post.get("video") or {}).get("mp4URL")
    if post.get("type") == "video" and mp4_url:
        try:
            if video_size(mp4_url) < MIN_VIDEO_BYTES:
                return "broken", post_id, "TikTok CDN refused the download; purge it in offtiktok and check again", post
        except Exception as error:
            return "broken", post_id, f"video file not reachable: {error}"[:300], post
    return "saved", post_id, None, post


def save_to_offtiktok(handle, tiktok_id):
    status, post_id, error, _ = fetch_into_offtiktok(f"https://www.tiktok.com/@{handle}/video/{tiktok_id}")
    return status, post_id, error


def save_single_video(tiktok_url):
    status, post_id, error, post = fetch_into_offtiktok(tiktok_url)
    tiktok_id = post.get("tiktokId")
    if not tiktok_id:
        match = re.search(r"/video/(\d+)", tiktok_url)
        tiktok_id = match.group(1) if match else tiktok_url
    handle = (post.get("author") or {}).get("handle") or (parse_handle(tiktok_url) or "")
    with db() as conn:
        conn.execute(
            """INSERT INTO videos (tiktok_id, handle, title, status, post_id, error, seen_at)
               VALUES (?, ?, ?, ?, ?, ?, ?)
               ON CONFLICT(tiktok_id) DO UPDATE SET status = excluded.status, post_id = excluded.post_id, error = excluded.error""",
            (tiktok_id, handle, (post.get("postDescription") or "").strip() or None, status, post_id, error, int(time.time())),
        )


def check_profile(handle, first_check):
    now = int(time.time())
    try:
        entries = list_profile_videos(handle, FIRST_LIST_COUNT if first_check else DAILY_LIST_COUNT)
    except Exception as error:
        with db() as conn:
            conn.execute(
                "UPDATE profiles SET last_checked = ?, last_error = ? WHERE handle = ?",
                (now, str(error)[:300], handle),
            )
        return

    with db() as conn:
        known = {row["tiktok_id"] for row in conn.execute("SELECT tiktok_id FROM videos WHERE handle = ?", (handle,))}
        for index, entry in enumerate(entries):
            if entry["id"] in known:
                continue
            status = "skipped" if first_check and index >= BACKFILL_COUNT else "pending"
            conn.execute(
                "INSERT OR IGNORE INTO videos (tiktok_id, handle, title, upload_date, status, seen_at) VALUES (?, ?, ?, ?, ?, ?)",
                (entry["id"], handle, entry.get("title"), entry.get("upload_date"), status, now),
            )
        to_fetch = [
            row["tiktok_id"]
            for row in conn.execute(
                "SELECT tiktok_id FROM videos WHERE handle = ? AND status IN ('pending', 'failed') ORDER BY upload_date DESC",
                (handle,),
            )
        ]

    for tiktok_id in to_fetch:
        status, post_id, error = save_to_offtiktok(handle, tiktok_id)
        with db() as conn:
            conn.execute(
                "UPDATE videos SET status = ?, post_id = ?, error = ? WHERE tiktok_id = ?",
                (status, post_id, error, tiktok_id),
            )

    with db() as conn:
        conn.execute(
            "UPDATE profiles SET last_checked = ?, last_error = NULL WHERE handle = ?",
            (int(time.time()), handle),
        )


def run_checks(handles=None):
    with open(LOCK_PATH, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        with db() as conn:
            rows = conn.execute("SELECT handle, last_checked FROM profiles ORDER BY handle").fetchall()
        for row in rows:
            if handles is None or row["handle"] in handles:
                check_profile(row["handle"], first_check=row["last_checked"] is None)


def run_checks_in_background(handles=None):
    threading.Thread(target=run_checks, args=(handles,), daemon=True).start()


def format_time(timestamp):
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(timestamp)) if timestamp else "never"


def format_date(upload_date):
    if upload_date and len(upload_date) == 8:
        return f"{upload_date[:4]}-{upload_date[4:6]}-{upload_date[6:]}"
    return ""


def render_page(message=""):
    e = html.escape
    with db() as conn:
        profiles = conn.execute(
            """
            SELECT p.*, COUNT(v.tiktok_id) FILTER (WHERE v.status = 'saved') AS saved
            FROM profiles p LEFT JOIN videos v ON v.handle = p.handle
            GROUP BY p.handle ORDER BY p.handle
            """
        ).fetchall()
        videos = conn.execute(
            """SELECT * FROM videos WHERE status NOT IN ('skipped', 'purged')
               ORDER BY COALESCE(upload_date, strftime('%Y%m%d', seen_at, 'unixepoch')) DESC, seen_at DESC LIMIT 300"""
        ).fetchall()

    profile_rows = "".join(
        f"""<tr>
          <td><a href="https://www.tiktok.com/@{e(p['handle'])}">@{e(p['handle'])}</a></td>
          <td>{p['saved']}</td>
          <td>{format_time(p['last_checked'])}</td>
          <td class="error">{e(p['last_error'] or '')}</td>
          <td><form method="post" action="/remove" onsubmit="return confirm('Stop following @{e(p['handle'])}?')">
            <input type="hidden" name="handle" value="{e(p['handle'])}"><button>Remove</button></form></td>
        </tr>"""
        for p in profiles
    ) or '<tr><td colspan="5">No profiles yet.</td></tr>'

    def video_card(v):
        title = e(v["title"] or "(no caption)")
        thumb = f"{OFFTIKTOK_PUBLIC_API_URL}/thumbnails/{e(v['tiktok_id'])}.jpg"
        if v["status"] == "saved" and v["post_id"]:
            link = f"{OFFTIKTOK_URL}/post/{v['post_id']}"
            return f"""<a class="card" href="{link}"><img src="{thumb}" loading="lazy" alt="">
              <div><b>@{e(v['handle'])}</b> {format_date(v['upload_date'])}<p>{title}</p></div></a>"""
        return f"""<div class="card {e(v['status'])}"><div class="placeholder">{e(v['status'])}</div>
          <div><b>@{e(v['handle'])}</b> {format_date(v['upload_date'])}<p>{title}</p>
          <p class="error">{e(v['error'] or '')}</p></div></div>"""

    cards = "".join(video_card(v) for v in videos) or "<p>No videos yet.</p>"
    notice = f'<p class="notice">{e(message)}</p>' if message else ""

    return f"""<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>TikTok follow</title>
<style>
  body {{ font-family: system-ui, sans-serif; background: #111; color: #eee; margin: 0 auto; max-width: 1100px; padding: 16px; }}
  a {{ color: #8cf; }}
  table {{ border-collapse: collapse; width: 100%; margin-bottom: 24px; }}
  td, th {{ text-align: left; padding: 6px 8px; border-bottom: 1px solid #333; vertical-align: top; }}
  form.inline {{ display: inline; }}
  input, button {{ background: #222; color: #eee; border: 1px solid #444; padding: 6px 10px; border-radius: 4px; }}
  .error {{ color: #f88; font-size: 0.85em; }}
  .notice {{ background: #234; padding: 8px 12px; border-radius: 4px; }}
  .grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 12px; }}
  .card {{ display: block; background: #1b1b1b; border-radius: 6px; overflow: hidden; color: inherit; text-decoration: none; }}
  .card img, .placeholder {{ width: 100%; aspect-ratio: 9/16; object-fit: cover; background: #222; display: flex; align-items: center; justify-content: center; color: #999; }}
  .card div {{ padding: 6px 8px; font-size: 0.85em; }}
  .card p {{ margin: 4px 0 0; overflow: hidden; display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical; }}
  .failed .placeholder, .broken .placeholder {{ color: #f88; }}
</style></head>
<body>
<h1>TikTok follow</h1>
{notice}
<form method="post" action="/add" class="inline">
  <input name="handle" placeholder="@handle or profile URL" size="32" required>
  <button>Follow</button>
</form>
<form method="post" action="/check" class="inline"><button>Check now</button></form>
<p><form method="post" action="/save" class="inline">
  <input name="url" placeholder="TikTok video link" size="48" required>
  <button>Save one video</button>
</form></p>
<p>Checked daily; new videos are saved to <a href="{OFFTIKTOK_URL}">offtiktok</a>.</p>
<table><tr><th>Profile</th><th>Saved</th><th>Last check</th><th>Last error</th><th></th></tr>{profile_rows}</table>
<div class="grid">{cards}</div>
</body></html>"""


class Handler(BaseHTTPRequestHandler):
    def send_html(self, body, status=200):
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def redirect(self, message=""):
        self.send_response(303)
        self.send_header("Location", "/?" + urllib.parse.urlencode({"message": message}) if message else "/")
        self.end_headers()

    def form(self):
        length = int(self.headers.get("Content-Length") or 0)
        return urllib.parse.parse_qs(self.rfile.read(length).decode())

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        if url.path != "/":
            self.send_html("<p>Not found</p>", 404)
            return
        message = urllib.parse.parse_qs(url.query).get("message", [""])[0]
        self.send_html(render_page(message))

    def do_POST(self):
        fields = self.form()
        if self.path == "/add":
            handle = parse_handle(fields.get("handle", [""])[0])
            if not handle:
                self.redirect("That doesn't look like a TikTok handle or profile URL.")
                return
            with db() as conn:
                inserted = conn.execute(
                    "INSERT OR IGNORE INTO profiles (handle, added_at) VALUES (?, ?)",
                    (handle, int(time.time())),
                ).rowcount
            if inserted:
                run_checks_in_background({handle})
                self.redirect(f"Following @{handle}. Fetching the latest {BACKFILL_COUNT} videos in the background.")
            else:
                self.redirect(f"Already following @{handle}.")
        elif self.path == "/remove":
            handle = parse_handle(fields.get("handle", [""])[0])
            if handle:
                with db() as conn:
                    conn.execute("DELETE FROM videos WHERE handle = ?", (handle,))
                    conn.execute("DELETE FROM profiles WHERE handle = ?", (handle,))
            self.redirect(f"Stopped following @{handle}. Saved videos stay in offtiktok.")
        elif self.path == "/save":
            tiktok_url = fields.get("url", [""])[0].strip()
            parsed = urllib.parse.urlparse(tiktok_url)
            hostname = parsed.hostname or ""
            if parsed.scheme not in ("http", "https") or not (hostname == "tiktok.com" or hostname.endswith(".tiktok.com")):
                self.redirect("That doesn't look like a TikTok link.")
                return
            threading.Thread(target=save_single_video, args=(tiktok_url,), daemon=True).start()
            self.redirect("Saving the video in the background. Reload in a few seconds.")
        elif self.path == "/check":
            run_checks_in_background()
            self.redirect("Checking all profiles in the background. Reload in a minute.")
        else:
            self.send_html("<p>Not found</p>", 404)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    init_db()
    if sys.argv[1] == "serve":
        ThreadingHTTPServer(("127.0.0.1", int(sys.argv[2])), Handler).serve_forever()
    elif sys.argv[1] == "check":
        run_checks()
