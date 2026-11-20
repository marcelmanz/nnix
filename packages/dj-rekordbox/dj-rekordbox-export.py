#!/usr/bin/env python3
"""Mirror a DJ folder into a Rekordbox-prepared USB export (Linux, no Rekordbox).

The export directory is a normal Rekordbox USB layout:

    PIONEER/rekordbox/exportLibrary.db   OneLibrary / Device Library Plus (new CDJs)
    PIONEER/rekordbox/export.pdb         legacy database (older CDJ/XDJ)
    PIONEER/USBANLZ/...                  BPM/key/waveform analysis
    Contents/<Artist>/<Album>/<file>     audio

``export`` makes the destination match ``--source``: new files are copied,
analysed (BPM, key, waveform, artwork), inserted into both databases, changed
tags are updated and files deleted from the source are removed from the export.
It is idempotent and keeps its own manifest in the export root.

This uses djsync (https://github.com/Pikkol0/djsync) for the Rekordbox database
and analysis code. It is not a reimplementation of Rekordbox.

Examples:
    dj-rekordbox init --root /var/lib/media/dj-rekordbox
    dj-rekordbox export --source /var/lib/media/dj --root /var/lib/media/dj-rekordbox
    dj-rekordbox status --root /var/lib/media/dj-rekordbox
    dj-rekordbox sync-usb --root /var/lib/media/dj-rekordbox --dest /run/media/me/CDJ --delete
"""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import logging
import os
import re
import shutil
import subprocess
import sys
import time
from collections.abc import Iterator, Sequence
from contextlib import contextmanager, nullcontext
from pathlib import Path
from typing import Any

from djsync.core import genre_playlists
from djsync.core.importer import ImportInfo, is_audio
from djsync.db import RekordboxUsbLibrary
from djsync.db.blank_key import template_files
from djsync.db.library.common import _safe_name
from djsync.db.usb import drive_filesystem, filesystem_compat

LOG = logging.getLogger("dj-rekordbox")

DB_REL = Path("PIONEER") / "rekordbox" / "exportLibrary.db"
PDB_REL = Path("PIONEER") / "rekordbox" / "export.pdb"
STATE_NAME = ".djsync-export.json"
LOCK_NAME = ".djsync-export.lock"
USB_MARKER = ".dj-rekordbox-export"
STATE_VERSION = 1

SKIP_DIRS = {
    ".stfolder",
    ".stversions",
    ".stignore",
    ".Trash",
    ".Trash-1000",
    "$RECYCLE.BIN",
    "System Volume Information",
    "DJSync imported",
    "DJSync_Backups",
    "PIONEER",
}
UNSUPPORTED_AUDIO_EXTS = {
    ".aifc",
    ".ape",
    ".m4b",
    ".mp4",
    ".oga",
    ".ogg",
    ".opus",
    ".webm",
    ".wma",
}
RESERVED_NAMES = {
    "CON",
    "PRN",
    "AUX",
    "NUL",
    *(f"COM{i}" for i in range(1, 10)),
    *(f"LPT{i}" for i in range(1, 10)),
}


# --------------------------------------------------------------------------- helpers


def setup_logging(verbose: int = 0) -> None:
    level = logging.DEBUG if verbose > 1 else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)s %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        stream=sys.stderr,
    )


def resolve_dir(value: str | Path) -> Path:
    return Path(value).expanduser().resolve()


def lib_rel(root: Path, path: Path) -> str:
    """Path as Rekordbox stores it: relative to the drive root, with a leading '/'."""
    return "/" + path.resolve().relative_to(root.resolve()).as_posix()


def safe_filename(name: str) -> str:
    stem, ext = os.path.splitext(name)
    stem = _safe_name(stem, "track")
    if stem.upper() in RESERVED_NAMES:
        stem = "_" + stem
    return stem + ext.lower()


_SPLIT = re.compile(r"\s+[-–—]\s+")


def _first(tags: Any, *keys: str) -> str:
    for key in keys:
        try:
            value = tags.get(key)
        except Exception:  # noqa: BLE001 - exotic tag types
            value = None
        if value:
            if isinstance(value, (list, tuple)):
                value = value[0]
            text = str(value).strip()
            if text:
                return text
    return ""


def _id3_first(tags: Any, *frame_ids: str) -> str:
    for frame_id in frame_ids:
        frame = tags.get(frame_id)
        if frame is None:
            continue
        value = getattr(frame, "text", None)
        if value:
            if isinstance(value, (list, tuple)):
                value = value[0]
            text = str(value).strip()
            if text:
                return text
    return ""


def read_info(path: Path) -> ImportInfo:
    """Read tags from AIFF/FLAC/WAV/MP3/M4A.

    djsync's importer uses mutagen ``easy=True``; mutagen does not expose ID3
    frames through the easy API for AIFF/WAV, so Bandcamp AIFFs would lose
    artist/album/genre. Handle ID3 explicitly and fall back to the filename.
    """
    title = artist = album = genre = label = year = track = isrc = ""
    try:
        import mutagen
        from mutagen.id3 import ID3

        raw = mutagen.File(str(path))
        tags = getattr(raw, "tags", None) if raw is not None else None
        if isinstance(tags, ID3):
            title = _id3_first(tags, "TIT2")
            artist = _id3_first(tags, "TPE1", "TPE2")
            album = _id3_first(tags, "TALB")
            genre = _id3_first(tags, "TCON")
            label = _id3_first(tags, "TPUB")
            year = _id3_first(tags, "TDRC", "TYER", "TDOR")
            track = _id3_first(tags, "TRCK")
            isrc = _id3_first(tags, "TSRC")
        else:
            easy = mutagen.File(str(path), easy=True)
            easy_tags = getattr(easy, "tags", None) if easy is not None else None
            if easy_tags:
                title = _first(easy_tags, "title")
                artist = _first(easy_tags, "artist", "albumartist")
                album = _first(easy_tags, "album")
                genre = _first(easy_tags, "genre")
                label = _first(easy_tags, "organization", "label", "publisher")
                year = _first(easy_tags, "date", "originaldate", "year")
                track = _first(easy_tags, "tracknumber")
                isrc = _first(easy_tags, "isrc")
    except Exception as exc:  # noqa: BLE001 - unreadable tags: the filename is enough
        LOG.info("Tags not read (%s): %s", path.name, exc)

    if not title:
        parts = _SPLIT.split(path.stem, maxsplit=1)
        if len(parts) == 2:
            artist = artist or parts[0].strip()
            title = parts[1].strip()
        else:
            title = path.stem

    meta: dict[str, Any] = {}
    if genre:
        meta["genre"] = genre
    if label:
        meta["label"] = label
    match = re.match(r"(\d{4})", year or "")
    if match:
        meta["year"] = int(match.group(1))
    match = re.match(r"(\d+)", track or "")
    if match:
        meta["track_no"] = int(match.group(1))
    if isrc:
        meta["isrc"] = isrc
    return ImportInfo(path, title.strip(), artist.strip(), album.strip() or None, meta)


def info_hash(info: Any) -> str:
    payload = {
        "title": info.title,
        "artist": info.artist,
        "album": info.album or "",
        "meta": info.meta,
    }
    raw = json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp-{os.getpid()}")
    try:
        tmp.write_bytes(data)
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


class ExportProgress:
    """JSON snapshot of a running export for the status page; a no-op without a path."""

    def __init__(self, path: Path | None, min_interval: float = 1.0) -> None:
        self.path = path
        self.min_interval = min_interval
        self.last_write = 0.0
        self.fields: dict[str, Any] = {"started": time.time()}

    def update(self, force: bool = False, **fields: Any) -> None:
        if self.path is None:
            return
        self.fields.update(fields)
        now = time.time()
        if not force and now - self.last_write < self.min_interval:
            return
        self.fields["updated"] = now
        self.last_write = now
        try:
            atomic_write(self.path, json.dumps(self.fields).encode("utf-8"))
        except OSError as exc:
            LOG.debug("Cannot write progress file %s: %s", self.path, exc)


@contextmanager
def exclusive_lock(root: Path) -> Iterator[None]:
    """One exporter / USB copy at a time. Blocking: a second run waits instead of failing."""
    root.mkdir(parents=True, exist_ok=True)
    lock_path = root / LOCK_NAME
    with open(lock_path, "a+", encoding="utf-8") as fh:
        fcntl.flock(fh.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(fh.fileno(), fcntl.LOCK_UN)


def load_state(root: Path) -> dict[str, Any]:
    path = root / STATE_NAME
    if not path.is_file():
        return {"version": STATE_VERSION, "tracks": {}}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        bad = path.with_name(f"{path.name}.bad-{int(time.time())}")
        LOG.warning(
            "Ignoring unreadable manifest %s (%s); renamed to %s", path, exc, bad
        )
        try:
            path.replace(bad)
        except OSError:
            pass
        return {"version": STATE_VERSION, "tracks": {}}
    if not isinstance(data, dict) or not isinstance(data.get("tracks"), dict):
        LOG.warning(
            "Manifest %s has an unexpected shape; starting with an empty manifest", path
        )
        return {"version": STATE_VERSION, "tracks": {}}
    data.setdefault("version", STATE_VERSION)
    return data


def save_state(root: Path, state: dict[str, Any]) -> None:
    payload = json.dumps(state, ensure_ascii=False, indent=1, sort_keys=True).encode(
        "utf-8"
    )
    atomic_write(root / STATE_NAME, payload)


def ensure_blank(root: Path, force: bool = False) -> bool:
    """Create a blank Rekordbox 7 export if the destination has no database yet."""
    db = root / DB_REL
    if db.is_file() and not force:
        return False
    if force:
        for rel in (
            DB_REL,
            PDB_REL,
            Path("PIONEER/rekordbox/exportExt.pdb"),
            Path("PIONEER/DEVSETTING.DAT"),
        ):
            (root / rel).unlink(missing_ok=True)
    if (
        root.exists()
        and any(root.iterdir())
        and not force
        # An export root should be dedicated. Refuse to drop a template into a random non-empty tree.
        and (root / "PIONEER").exists()
        and any((root / "PIONEER").iterdir())
    ):
        raise SystemExit(
            f"{root} already contains a PIONEER tree but no exportLibrary.db; "
            "refusing to overwrite it (use --force-init if this is intentional)"
        )
    root.mkdir(parents=True, exist_ok=True)
    LOG.info("Creating a blank Rekordbox export in %s", root)
    for name, data in template_files().items():
        atomic_write(root / name, data)
    return True


def open_library(root: Path, read_only: bool = False) -> RekordboxUsbLibrary:
    return RekordboxUsbLibrary(
        root,
        read_only=read_only,
        analyze=not read_only,
        artwork=not read_only,
        pdb_sync="auto",
        pdb_allow_growth=True,
    )


def scan_source(source: Path) -> tuple[list[tuple[str, Path]], set[str], list[str]]:
    """Return (audio files as (relative path, absolute path), all relative paths, unsupported files)."""
    audio: list[tuple[str, Path]] = []
    present: set[str] = set()
    unsupported: list[str] = []
    for dirpath, dirnames, filenames in os.walk(source):
        dirnames[:] = sorted(
            d for d in dirnames if not d.startswith(".") and d not in SKIP_DIRS
        )
        for name in sorted(filenames):
            if name.startswith("."):
                continue
            path = Path(dirpath) / name
            try:
                rel = path.relative_to(source).as_posix()
            except ValueError:
                continue
            present.add(rel)
            if is_audio(path):
                audio.append((rel, path))
            elif path.suffix.lower() in UNSUPPORTED_AUDIO_EXTS:
                unsupported.append(rel)
    return audio, present, unsupported


def choose_destination(
    lib: RekordboxUsbLibrary,
    info: Any,
    source_path: Path,
    source_root: Path,
    previous: dict[str, Any] | None,
    owners: dict[str, str],
    by_path: dict[str, str],
    rel: str,
) -> tuple[Path, str]:
    """Pick a unique path under Contents/. Existing manifest entry wins; otherwise Artist/Album."""
    root = lib.drive.root
    if source_root == root.resolve() or root.resolve() in source_root.parents:
        return source_path, lib_rel(root, source_path)
    if previous and previous.get("dest"):
        previous_dest = str(previous["dest"])
        owner = owners.get(previous_dest.casefold())
        if owner in (None, rel):
            actual = by_path.get(previous_dest.casefold(), previous_dest)
            return root / actual.lstrip("/"), actual

    if info.artist or info.album:
        folder = lib.default_download_dir(
            info.artist or "Unknown Artist", info.album or ""
        )
    else:
        parent = source_path.parent.relative_to(source_root)
        parts = [_safe_name(part, "Unknown") for part in parent.parts]
        folder = lib.contents_root.joinpath(*parts)

    name = safe_filename(source_path.name)
    stem, ext = os.path.splitext(name)
    candidate = folder / name
    counter = 2
    while True:
        candidate_rel = lib_rel(root, candidate)
        key = candidate_rel.casefold()
        owner = owners.get(key)
        existing = by_path.get(key)
        if owner == rel:
            actual = existing or candidate_rel
            return root / actual.lstrip("/"), actual
        if owner is None and existing is not None:
            existing_path = root / existing.lstrip("/")
            try:
                if existing_path.is_file() and os.path.samefile(
                    source_path, existing_path
                ):
                    return existing_path, existing
            except OSError:
                pass
            # The path is used by a different track (or the manifest was lost):
            # never overwrite it, pick a suffixed name instead.
            candidate = folder / f"{stem} ({counter}){ext}"
            counter += 1
            continue
        if owner is None and existing is None:
            return candidate, candidate_rel
        candidate = folder / f"{stem} ({counter}){ext}"
        counter += 1
        if counter > 10000:
            raise RuntimeError(
                f"Could not find a free destination name for {source_path}"
            )


def ensure_export_file(source: Path, dest: Path) -> bool:
    """Copy (or hardlink) source to dest when needed. Returns True when dest was (re)written."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists():
        try:
            if os.path.samefile(source, dest):
                return False
        except OSError:
            pass
    tmp = dest.with_name(f".{dest.name}.djsync-tmp-{os.getpid()}")
    tmp.unlink(missing_ok=True)
    try:
        try:
            os.link(source, tmp)
        except OSError:
            shutil.copy2(source, tmp)
        os.replace(tmp, dest)
    finally:
        tmp.unlink(missing_ok=True)
    return True


def remove_empty_dirs(lib: RekordboxUsbLibrary) -> None:
    for base in (lib.contents_root, lib.drive.root / "PIONEER" / "USBANLZ"):
        if not base.is_dir():
            continue
        for dirpath, _dirnames, _filenames in os.walk(base, topdown=False):
            path = Path(dirpath)
            if path == base:
                continue
            try:
                path.rmdir()
            except OSError:
                pass


def unlink_inside(root: Path, rel_path: str) -> bool:
    target = (root / rel_path.lstrip("/")).resolve()
    root = root.resolve()
    if root != target and root not in target.parents:
        LOG.warning("Refusing to remove path outside the export root: %s", rel_path)
        return False
    try:
        target.unlink()
        return True
    except FileNotFoundError:
        return False
    except OSError as exc:
        LOG.warning("Could not remove %s: %s", target, exc)
        return False


def genre_sync(lib: RekordboxUsbLibrary, state: dict[str, Any], enabled: bool) -> None:
    if not enabled:
        return
    cfg = state.get("genre_config")
    if not isinstance(cfg, dict):
        cfg = genre_playlists.default_config()
        # Recover the folder/playlist ids if the manifest was lost; otherwise
        # sync() would try to create playlists whose names already exist.
        playlists = list(lib.list_playlists())
        root_folder = next(
            (
                p
                for p in playlists
                if p.is_folder
                and p.parent_id == 0
                and p.name == genre_playlists.ROOT_FOLDER
            ),
            None,
        )
        if root_folder is not None:
            cfg["root_id"] = root_folder.playlist_id
            genres_folder = next(
                (
                    p
                    for p in playlists
                    if p.is_folder
                    and p.parent_id == root_folder.playlist_id
                    and p.name == genre_playlists.GENRES_FOLDER
                ),
                None,
            )
            if genres_folder is not None:
                cfg["folder_id"] = genres_folder.playlist_id
                for playlist in playlists:
                    if (
                        playlist.is_folder
                        or playlist.parent_id != genres_folder.playlist_id
                    ):
                        continue
                    cfg["groups"].append(
                        {
                            "name": playlist.name,
                            "genres": [playlist.name],
                            "enabled": True,
                            "playlist_id": playlist.playlist_id,
                            "members": [
                                t.content_id
                                for t in lib.get_playlist_tracks(playlist.playlist_id)
                            ],
                        }
                    )
        state["genre_config"] = cfg
    cfg["enabled"] = True
    cfg["auto"] = True

    track_genres = lib.track_genres()
    counts = genre_playlists.genre_counts(track_genres)
    known = {
        genre.casefold()
        for group in cfg.get("groups", [])
        for genre in group.get("genres", [])
    }
    for genre in sorted(counts):
        if genre.casefold() not in known:
            cfg.setdefault("groups", []).append(
                {
                    "name": genre,
                    "genres": [genre],
                    "enabled": True,
                    "playlist_id": 0,
                    "members": [],
                }
            )

    report = genre_playlists.sync(lib, cfg, track_genres)
    LOG.info(
        "Genre playlists: %d created, %d tracks added, %d removed%s",
        report.created,
        report.added,
        report.removed,
        f", {len(report.disabled)} disabled" if report.disabled else "",
    )


def refresh_library_maps(
    lib: RekordboxUsbLibrary,
) -> tuple[dict[int, Any], dict[str, str]]:
    tracks = lib.list_tracks()
    by_id = {int(t.content_id): t for t in tracks}
    by_path = {t.path.casefold(): t.path for t in tracks}
    return by_id, by_path


# --------------------------------------------------------------------------- commands


def cmd_init(args: argparse.Namespace) -> int:
    root = resolve_dir(args.root)
    ensure_blank(root, force=args.force)
    with open_library(root) as lib:
        status = lib.pdb_status()
        LOG.info(
            "Library ready: %d tracks, export.pdb=%s", lib.track_count(), status.state
        )
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    root = resolve_dir(args.root)
    if not (root / DB_REL).is_file():
        print(
            f"{root}: no Rekordbox exportLibrary.db (run: dj-rekordbox init --root {root})"
        )
        return 1
    with exclusive_lock(root), open_library(root, read_only=True) as lib:
        tracks = lib.list_tracks()
        playlists = lib.list_playlists()
        status = lib.pdb_status()
        state = load_state(root)
        managed = state.get("tracks", {})
        missing_dest = sum(
            1
            for entry in managed.values()
            if not (root / str(entry.get("dest", "")).lstrip("/")).is_file()
        )
        managed_dests = {
            str(entry.get("dest", "")).casefold()
            for entry in managed.values()
            if entry.get("dest")
        }
        unmanaged = sum(1 for t in tracks if t.path.casefold() not in managed_dests)
        print(f"root:       {root}")
        print(f"tracks:     {len(tracks)}")
        print(f"playlists:  {len(playlists)}")
        print(
            f"export.pdb: {status.state}"
            + (f" ({status.detail})" if getattr(status, "detail", "") else "")
        )
        print(
            f"manifest:   {len(managed)} entries, {missing_dest} missing files, {unmanaged} unmanaged tracks"
        )
        print(
            f"pdb tracks: {status.pdb_tracks} (library {status.ol_tracks}, "
            f"missing {status.missing_tracks}, changed {status.changed_tracks}, "
            f"pending removals {status.pending_removals})"
        )
    return 0


def cmd_export(args: argparse.Namespace) -> int:
    source = resolve_dir(args.source)
    root = resolve_dir(args.root)
    if not source.is_dir():
        LOG.error("Source folder does not exist: %s", source)
        return 1
    if source in root.parents:
        LOG.error("The export root must not be inside the source folder")
        return 1
    in_place = root == source or root in source.parents

    with exclusive_lock(root):
        if args.dry_run and not (root / DB_REL).is_file():
            LOG.error("No export at %s yet; run export without --dry-run once", root)
            return 1
        progress = ExportProgress(
            None if args.dry_run or not args.progress_file else Path(args.progress_file)
        )
        progress.update(force=True, phase="scanning")
        created = False if args.dry_run else ensure_blank(root, force=args.force_init)
        state = load_state(root)
        present: set[str] = set()
        audio, present, unsupported = scan_source(source)
        if args.limit and args.limit > 0:
            audio = audio[: args.limit]
        if unsupported:
            LOG.warning(
                "Ignoring %d unsupported audio file(s) (CDJs do not play %s): %s%s",
                len(unsupported),
                ", ".join(sorted(UNSUPPORTED_AUDIO_EXTS)),
                ", ".join(unsupported[:8]),
                " …" if len(unsupported) > 8 else "",
            )
        LOG.info(
            "Source %s: %d audio file(s)%s",
            source,
            len(audio),
            " (new blank export created)" if created else "",
        )

        counts = {
            "added": 0,
            "updated": 0,
            "unchanged": 0,
            "young": 0,
            "failed": 0,
            "removed": 0,
        }
        progress.update(
            force=True, phase="exporting", total=len(audio), processed=0, counts=counts
        )
        with open_library(root, read_only=args.dry_run) as lib:
            tracks_by_id, by_path = refresh_library_maps(lib)
            owners: dict[str, str] = {}
            for rel, entry in state.get("tracks", {}).items():
                dest = str(entry.get("dest", ""))
                if dest:
                    owners[dest.casefold()] = rel

            batch = nullcontext() if args.dry_run else lib.long_batch()
            with batch:
                dirty = 0
                now = time.time()
                for index, (rel, path) in enumerate(audio, start=1):
                    progress.update(processed=index - 1, current=rel)
                    try:
                        st = path.stat()
                    except OSError as exc:
                        LOG.warning("Cannot stat %s: %s", path, exc)
                        counts["failed"] += 1
                        continue
                    if args.min_age > 0 and now - st.st_mtime < args.min_age:
                        counts["young"] += 1
                        LOG.debug(
                            "Still being written (age %.0fs): %s",
                            now - st.st_mtime,
                            rel,
                        )
                        continue

                    previous = state.get("tracks", {}).get(rel)
                    previous_cid = (
                        int(previous.get("content_id") or 0) if previous else 0
                    )
                    previous_track = tracks_by_id.get(previous_cid)
                    previous_dest_rel = (
                        str(previous.get("dest", "")) if previous else ""
                    )
                    previous_dest = (
                        (root / previous_dest_rel.lstrip("/"))
                        if previous_dest_rel
                        else None
                    )
                    source_changed = bool(
                        previous
                        and (
                            previous.get("size") != st.st_size
                            or previous.get("mtime_ns") != st.st_mtime_ns
                        )
                    )
                    # Fast path: do not open/parse every file on every timer run.
                    # Tag writers (dj-enrich, dj-genres, tagr) change mtime, so a
                    # stat match is a reliable "nothing to do" signal.
                    if (
                        previous
                        and previous_track
                        and previous_track.is_analysed
                        and previous_dest is not None
                        and previous_dest.is_file()
                        and not source_changed
                    ):
                        counts["unchanged"] += 1
                        LOG.debug("= %s", rel)
                        continue

                    try:
                        info = read_info(path)
                        tags_hash = info_hash(info)
                        tags_changed = bool(
                            previous and previous.get("tags") != tags_hash
                        )
                        dest, dest_rel = choose_destination(
                            lib, info, path, source, previous, owners, by_path, rel
                        )

                        if args.dry_run:
                            action = "update" if previous else "add"
                            LOG.info("would %s %s -> %s", action, rel, dest_rel)
                            counts["updated" if previous else "added"] += 1
                            continue

                        ensure_export_file(path, dest)
                        if (
                            previous_track
                            and previous_dest_rel
                            and previous_dest_rel.casefold() != dest_rel.casefold()
                        ):
                            previous_track = lib.relink_track(previous_cid, dest)
                            by_path.pop(previous_dest_rel.casefold(), None)
                            by_path[dest_rel.casefold()] = dest_rel
                            LOG.info("~ %s moved %s -> %s", rel, previous_dest_rel, dest_rel)
                        existed = bool(previous_track or dest_rel.casefold() in by_path)

                        track = lib.add_track(
                            dest,
                            info.title,
                            info.artist,
                            info.album,
                            meta=info.meta,
                        )
                        cid = int(track.content_id)
                        if source_changed or not track.is_analysed:
                            # add_track() reuses an existing row without refreshing its fileSize/ANLZ.
                            if existed and source_changed:
                                try:
                                    track = lib.relink_track(cid, dest)
                                except Exception as exc:  # noqa: BLE001 - size bookkeeping must not lose the track
                                    LOG.debug(
                                        "Could not refresh file metadata for %s: %s",
                                        dest_rel,
                                        exc,
                                    )
                            try:
                                track = lib.analyze_track(cid, force=True)
                            except Exception as exc:  # noqa: BLE001 - the old analysis remains usable
                                LOG.warning(
                                    "Re-analysis failed for %s (old analysis kept): %s",
                                    rel,
                                    exc,
                                )
                        if existed and tags_changed:
                            try:
                                track = lib.edit_track_metadata(
                                    cid,
                                    title=info.title,
                                    artist=info.artist,
                                    album=info.album or "",
                                    year=int(info.meta.get("year") or 0),
                                    genre=info.meta.get("genre") or "",
                                )
                            except Exception as exc:  # noqa: BLE001 - metadata update is best effort
                                LOG.warning(
                                    "Metadata update failed for %s: %s", rel, exc
                                )

                        entry = {
                            "dest": dest_rel,
                            "content_id": cid,
                            "size": st.st_size,
                            "mtime_ns": st.st_mtime_ns,
                            "tags": tags_hash,
                            "title": info.title,
                            "artist": info.artist,
                            "album": info.album or "",
                            "genre": info.meta.get("genre") or "",
                        }
                        state.setdefault("tracks", {})[rel] = entry
                        owners[dest_rel.casefold()] = rel
                        by_path[dest_rel.casefold()] = dest_rel
                        tracks_by_id[cid] = track
                        counts["updated" if existed else "added"] += 1
                        dirty += 1
                        LOG.info(
                            "+ %s -> %s%s",
                            rel,
                            dest_rel,
                            " (updated)" if existed else "",
                        )
                        if lib.last_problems:
                            LOG.warning(
                                "  partial analysis: %s", "; ".join(lib.last_problems)
                            )
                        if dirty % 25 == 0:
                            save_state(root, state)
                    except Exception as exc:
                        counts["failed"] += 1
                        LOG.error(
                            "Failed to export %s: %s",
                            rel,
                            exc,
                            exc_info=args.verbose > 1,
                        )

                progress.update(
                    force=True, phase="finishing", processed=len(audio), current=None
                )
                if args.prune and not args.dry_run:
                    for rel, entry in list(state.get("tracks", {}).items()):
                        if rel in present:
                            continue
                        cid = int(entry.get("content_id") or 0)
                        dest = str(entry.get("dest", ""))
                        try:
                            if cid and cid in tracks_by_id:
                                lib.delete_track(cid, delete_file=not in_place)
                            elif dest:
                                unlink_inside(root, dest)
                            del state["tracks"][rel]
                            owners.pop(dest.casefold(), None)
                            counts["removed"] += 1
                            LOG.info("- %s (gone from source)", rel)
                        except Exception as exc:  # noqa: BLE001 - keep going
                            counts["failed"] += 1
                            LOG.error("Failed to remove %s: %s", rel, exc)
                    if counts["removed"]:
                        remove_empty_dirs(lib)

                if not args.dry_run and args.genre_playlists:
                    try:
                        genre_sync(lib, state, enabled=True)
                    except Exception as exc:  # noqa: BLE001 - playlists must not break the export
                        LOG.error("Genre playlist sync failed: %s", exc)

            if not args.dry_run:
                save_state(root, state)
                status = lib.pdb_status()
                if status.state not in ("ok", "absent", "off"):
                    LOG.error(
                        "export.pdb is not up to date (%s): %s",
                        status.state,
                        getattr(status, "detail", ""),
                    )
                LOG.info(
                    "Done: %d added, %d updated, %d unchanged, %d removed, %d young, %d failed; "
                    "%d tracks, export.pdb=%s",
                    counts["added"],
                    counts["updated"],
                    counts["unchanged"],
                    counts["removed"],
                    counts["young"],
                    counts["failed"],
                    lib.track_count(),
                    status.state,
                )
                progress.update(
                    force=True,
                    phase="done",
                    finished=time.time(),
                    pdb=status.state,
                    tracks=lib.track_count(),
                )
                if status.state in ("stale", "unsupported"):
                    return 1
            else:
                LOG.info(
                    "Dry run: %d would be added, %d updated, %d unchanged, %d young, %d failed",
                    counts["added"],
                    counts["updated"],
                    counts["unchanged"],
                    counts["young"],
                    counts["failed"],
                )
    return 0


def cmd_sync_usb(args: argparse.Namespace) -> int:
    root = resolve_dir(args.root)
    dest = resolve_dir(args.dest)
    if not (root / DB_REL).is_file():
        LOG.error("No export at %s (run: dj-rekordbox init/export)", root)
        return 1
    if not dest.is_dir():
        LOG.error("Destination %s does not exist; mount the USB stick first", dest)
        return 1
    if dest == root or root in dest.parents or dest in root.parents:
        LOG.error("Source and destination must be different trees")
        return 1

    with exclusive_lock(root):
        marker = dest / USB_MARKER
        has_db = (dest / DB_REL).is_file()
        if has_db and not marker.is_file() and not args.force:
            LOG.error(
                "%s already contains a Rekordbox library but no %s marker; "
                "refusing to overwrite it (use --force if sure)",
                dest,
                USB_MARKER,
            )
            return 1

        fs = drive_filesystem(dest)
        compat = filesystem_compat(fs)
        LOG.info("Destination %s: filesystem %s", dest, fs or "unknown")
        if compat == "unsupported":
            LOG.error(
                "%s is not readable by CDJs (FAT16/FAT32 required, exFAT only on recent models)",
                fs,
            )
            if not args.force:
                return 1
        elif compat == "recent_only":
            LOG.warning(
                "exFAT works only on newer CDJ-2000NXS2/XDJ models; FAT32 is safer"
            )
        elif compat == "":
            LOG.warning("Unknown filesystem; CDJs usually require FAT16/FAT32")

        total = 0
        excluded = {"DJSync_Backups", LOCK_NAME, STATE_NAME, USB_MARKER}
        for path in root.rglob("*"):
            if path.is_file() and not excluded.intersection(
                path.relative_to(root).parts
            ):
                try:
                    total += path.stat().st_size
                except OSError:
                    pass
        free = shutil.disk_usage(dest).free
        margin = 64 * 1024 * 1024
        if total + margin > free:
            LOG.error(
                "Not enough space on %s: need %.1f MiB, free %.1f MiB",
                dest,
                (total + margin) / 1048576,
                free / 1048576,
            )
            if not args.force:
                return 1

        cmd = [
            "rsync",
            "-a",
            "--human-readable",
            "--info=progress2",
            "--modify-window=2",
            "--filter=P /*",
            "--exclude=/DJSync_Backups/",
            f"--exclude=/{STATE_NAME}",
            f"--exclude=/{LOCK_NAME}",
            f"--exclude=/{USB_MARKER}",
            "--exclude=*.db-wal",
            "--exclude=*.db-shm",
        ]
        if args.delete:
            cmd.append("--delete")
        cmd.extend([f"{root}/", f"{dest}/"])
        LOG.info(
            "Copying export to %s%s",
            dest,
            " (deleting removed files)" if args.delete else "",
        )
        subprocess.run(cmd, check=True)
        os.sync()
        marker.write_text(
            f"dj-rekordbox export copied {time.strftime('%Y-%m-%d %H:%M:%S')}\n",
            encoding="utf-8",
        )
        LOG.info("USB copy complete: %s", dest)
    return 0


# --------------------------------------------------------------------------- CLI


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="dj-rekordbox",
        description="Mirror a DJ folder into a Rekordbox USB export and copy it to a stick.",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="count",
        default=0,
        help="more logging (repeat for debug)",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_init = sub.add_parser("init", help="create a blank Rekordbox export")
    p_init.add_argument("--root", default="/var/lib/media/dj")
    p_init.add_argument(
        "--force",
        action="store_true",
        help="overwrite an existing export (destructive)",
    )
    p_init.set_defaults(func=cmd_init)

    p_export = sub.add_parser("export", help="sync a DJ folder into the export")
    p_export.add_argument("--source", default="/var/lib/media/dj")
    p_export.add_argument("--root", default="/var/lib/media/dj")
    p_export.add_argument(
        "--min-age",
        type=float,
        default=120.0,
        help="skip files modified less than N seconds ago",
    )
    p_export.add_argument(
        "--limit", type=int, default=0, help="only process the first N files (testing)"
    )
    p_export.add_argument(
        "--prune",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="remove tracks deleted from the source (default: on)",
    )
    p_export.add_argument(
        "--genre-playlists",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="maintain genre playlists (default: on)",
    )
    p_export.add_argument(
        "--force-init",
        action="store_true",
        help="create a blank export even if non-empty",
    )
    p_export.add_argument(
        "--dry-run", action="store_true", help="show what would change, do not write"
    )
    p_export.add_argument(
        "--progress-file", help="keep a JSON progress snapshot here (status page)"
    )
    p_export.set_defaults(func=cmd_export)

    p_status = sub.add_parser("status", help="show library and export.pdb status")
    p_status.add_argument("--root", default="/var/lib/media/dj")
    p_status.set_defaults(func=cmd_status)

    p_usb = sub.add_parser("sync-usb", help="copy the export to a FAT32 USB stick")
    p_usb.add_argument("--root", default="/var/lib/media/dj")
    p_usb.add_argument("--dest", required=True, help="mount point of the USB stick")
    p_usb.add_argument(
        "--delete",
        action="store_true",
        help="delete files on the stick that are gone from the export",
    )
    p_usb.add_argument(
        "--force",
        action="store_true",
        help="allow a non-FAT destination / overwrite an unknown library",
    )
    p_usb.set_defaults(func=cmd_sync_usb)

    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    setup_logging(args.verbose)
    try:
        return int(args.func(args))
    except KeyboardInterrupt:
        LOG.error("Interrupted")
        return 130
    except SystemExit:
        raise
    except Exception as exc:
        LOG.error("%s", exc, exc_info=args.verbose > 1)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
