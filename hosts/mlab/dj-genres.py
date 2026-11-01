#!/usr/bin/env python3
"""Copy GENRE from the music/ FLACs (tagged by beets) onto the matching dj/ AIFFs.
Albums are paired by bandcampsync's bandcamp_item_id.txt. Idempotent.

Usage: dj-genres.py MUSIC_DIR DJ_DIR
"""

import os
import sys

from mutagen import File
from mutagen.id3 import ID3, TCON

AUDIO_EXTS = {".flac", ".aif", ".aiff", ".aifc"}


def albums_by_item_id(root):
    albums = {}
    for dirpath, _, files in os.walk(root):
        if "bandcamp_item_id.txt" not in files:
            continue
        with open(os.path.join(dirpath, "bandcamp_item_id.txt")) as f:
            item_id = f.read().strip()
        tracks = [
            os.path.join(dirpath, name)
            for name in sorted(files)
            if os.path.splitext(name)[1].lower() in AUDIO_EXTS
        ]
        albums[item_id] = tracks
    return albums


def album_genres(flacs):
    for path in flacs:
        genres = (File(path) or {}).get("genre")
        if genres:
            return genres
    return None


def main(music_dir, dj_dir):
    music_albums = albums_by_item_id(music_dir)
    done = failed = skipped = 0
    for item_id, aiffs in albums_by_item_id(dj_dir).items():
        genres = album_genres(music_albums.get(item_id, []))
        if not genres:
            skipped += len(aiffs)
            continue
        genre = ", ".join(genres)
        for path in aiffs:
            try:
                audio = File(path)
                if audio.tags is None:
                    audio.tags = ID3()
                if audio.tags.get("TCON") and audio.tags["TCON"].text == [genre]:
                    skipped += 1
                    continue
                audio.tags.add(TCON(encoding=3, text=[genre]))
                audio.save()
            except Exception as e:
                failed += 1
                print(f"FAIL {path}: {e}", file=sys.stderr)
                continue
            done += 1
            print(f"genre={genre}  {path}", flush=True)
    print(f"tagged={done} failed={failed} skipped={skipped}")


if __name__ == "__main__":
    main(*(sys.argv[1:] or ["/var/lib/media/music", "/var/lib/media/dj"]))
