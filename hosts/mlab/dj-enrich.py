#!/usr/bin/env python3
"""Tag DJ/music library files with BPM and musical key. Idempotent:
files that already have both tags are skipped, so rerun after every sync.

Usage: dj-enrich.py DIR [DIR ...]   (no args = /var/lib/media/dj + /var/lib/media/music)
"""
import os
import re
import subprocess
import sys
import tempfile

from mutagen import File
from mutagen.flac import FLAC
from mutagen.oggflac import OggFLAC
from mutagen.oggopus import OggOpus
from mutagen.oggvorbis import OggVorbis
from mutagen.aiff import AIFF
from mutagen.id3 import ID3, TBPM, TKEY
from mutagen.mp3 import MP3

VORBIS = (FLAC, OggFLAC, OggOpus, OggVorbis)
EXTS = {".flac", ".ogg", ".oga", ".opus", ".mp3", ".aif", ".aiff", ".aifc"}


def sh(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=900)


def complain(name, r):
    raise RuntimeError(f"{name} rc={r.returncode} out={r.stdout[:200]!r} err={r.stderr[:200]!r}")


def analyze_bpm(path):
    from aubio import source, tempo
    win_s, hop_s = 1024, 512
    s = source(path, samplerate=0, hop_size=hop_s)  # ledfx fork: samplerate comes FIRST positionally
    o = tempo("default", win_s, hop_s, s.samplerate)
    while True:
        samples, read = s()
        o(samples)
        if read < hop_s:
            break
    bpm = float(o.get_bpm())
    if not (0 < bpm == bpm):  # nan/zero => no beat found
        raise RuntimeError(f"aubio detected no tempo (bpm={bpm!r})")
    return f"{bpm:.3f}"


def analyze_key(path):
    # keyfinder-cli fails to resample 24-bit aiff itself -> decode to 16-bit wav first
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        r = sh(["ffmpeg", "-v", "error", "-y", "-i", path, "-vn", "-ac", "1", "-ar", "44100", tmp.name])
        if r.returncode != 0:
            complain("ffmpeg", r)
        r = sh(["keyfinder-cli", "-n", "standard", tmp.name])
    if r.returncode != 0 or not r.stdout.strip():
        complain("keyfinder-cli", r)
    return r.stdout.strip()


def analyze(path, need_bpm, need_key):
    bpm = key = None
    problems = []
    if need_bpm:
        try:
            bpm = analyze_bpm(path)
        except Exception as e:
            problems.append(f"bpm: {e}")
    if need_key:
        try:
            key = analyze_key(path)
        except Exception as e:
            problems.append(f"key: {e}")
    return bpm, key, problems


def process(path):
    audio = File(path)
    if audio is None:
        raise ValueError("unreadable")
    vorbis = isinstance(audio, VORBIS)
    id3 = isinstance(audio, (MP3, AIFF))
    if not (vorbis or id3):
        raise ValueError(f"unsupported type: {type(audio).__name__}")

    if vorbis:
        have = {k.lower() for k in audio.keys()}
        missing_bpm, missing_key = "bpm" not in have, not ({"initialkey", "key"} & have)
    else:
        tags = audio.tags
        missing_bpm = tags is None or "TBPM" not in tags
        missing_key = tags is None or "TKEY" not in tags
    if not (missing_bpm or missing_key):
        return None

    try:
        bpm, key, problems = analyze(path, missing_bpm, missing_key)
    except Exception as e:
        raise RuntimeError(str(e)) from None
    if not (bpm or key):
        raise RuntimeError("; ".join(problems))
    if vorbis:
        if bpm:
            audio["BPM"] = bpm
        if key:
            audio["INITIALKEY"] = key
    else:
        if audio.tags is None:
            audio.tags = ID3()
        if bpm:
            audio.tags.add(TBPM(encoding=3, text=[bpm]))
        if key:
            audio.tags.add(TKEY(encoding=3, text=[key]))
    audio.save()
    return bpm, key, "; ".join(problems)


def main(dirs):
    done = failed = skipped = 0
    for root in dirs:
        for dirpath, _, files in os.walk(root):
            for name in sorted(files):
                if os.path.splitext(name)[1].lower() not in EXTS:
                    continue
                path = os.path.join(dirpath, name)
                try:
                    result = process(path)
                except Exception as e:  # per-file failures must not kill a sync run
                    failed += 1
                    print(f"FAIL {path}: {e}", file=sys.stderr)
                    continue
                if result is None:
                    skipped += 1
                    continue
                done += 1
                bpm, key, warn = result
                print(f"bpm={bpm} key={key}{f'  (partial: {warn})' if warn else ''}  {path}", flush=True)
    print(f"enriched={done} failed={failed} already-tagged={skipped}")


if __name__ == "__main__":
    main(sys.argv[1:] or ["/var/lib/media/dj", "/var/lib/media/music"])
