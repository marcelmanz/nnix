"""Cut dynamically inserted ad breaks out of downloaded podcast episodes.

Some shows play the same sting on both sides of every ad break, so audio between two stings a
few minutes apart is an ad, and so is anything trailing the outro sting.
"""

import json
import os
import subprocess
import time
from pathlib import Path

import numpy as np

SECONDS_PER_ITEM = 0.1238
MAX_BIT_ERROR_RATE = 0.25
STING_SECONDS = 6.5
MAX_BREAK_SECONDS = 240
OUTRO_SECONDS = 11
POST_ROLL_WINDOW_SECONDS = 180
# audiobookshelf may still be writing anything newer
MIN_AGE_SECONDS = 600
AUDIO_SUFFIXES = {".mp3", ".m4a", ".aac", ".ogg", ".opus"}

PODCAST_DIR = Path(os.environ["PODCAST_DIR"])
STATE_DIR = Path(os.environ["STATE_DIRECTORY"])
DRY_RUN = os.environ.get("DRY_RUN") == "1"
STINGS = {
    show: np.array(fp, dtype=np.uint32)
    for show, fp in json.loads(Path(os.environ["SHOWS_FILE"]).read_text()).items()
}


def fingerprint(path):
    out = subprocess.run(
        ["fpcalc", "-raw", "-length", "0", str(path)],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    fields = dict(line.split("=", 1) for line in out.splitlines() if "=" in line)
    return np.array(
        [int(v) for v in fields["FINGERPRINT"].split(",")], dtype=np.uint32
    ), float(fields["DURATION"])


def find_stings(episode, sting):
    windows = np.lib.stride_tricks.sliding_window_view(episode, len(sting))
    error_rate = np.bitwise_count(windows ^ sting).sum(axis=1) / (32 * len(sting))
    hits = []
    for i in np.argsort(error_rate):
        if error_rate[i] > MAX_BIT_ERROR_RATE:
            break
        if all(abs(i - h) > len(sting) for h in hits):
            hits.append(i)
    return sorted(h * SECONDS_PER_ITEM for h in hits)


def plan_cuts(stings, duration):
    cuts = [
        (first + STING_SECONDS, second + STING_SECONDS)
        for first, second in zip(stings, stings[1:])
        if second - first < MAX_BREAK_SECONDS
    ]
    if stings and OUTRO_SECONDS + 5 < duration - stings[-1] < POST_ROLL_WINDOW_SECONDS:
        cuts.append((stings[-1] + OUTRO_SECONDS, duration))
    merged = []
    for start, end in cuts:
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(end, merged[-1][1]))
        else:
            merged.append((start, end))
    return merged


def cut(path, cuts):
    keep, position = [], 0.0
    for start, end in cuts:
        keep.append((position, start))
        position = end
    quoted = str(path).replace("'", r"'\''")
    listing = "".join(
        f"file '{quoted}'\ninpoint {start:.3f}\noutpoint {end:.3f}\n"
        for start, end in keep
    )
    listing += f"file '{quoted}'\ninpoint {position:.3f}\n"
    listing_path = STATE_DIR / "concat.txt"
    listing_path.write_text(listing)
    # dotfile: audiobookshelf's scanner ignores it until the rename
    partial = path.with_name(f".adcut-{path.name}")
    subprocess.run(
        [
            "ffmpeg",
            "-v",
            "error",
            "-y",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            str(listing_path),
            "-i",
            str(path),
            "-map",
            "0:a",
            "-map_metadata",
            "1",
            "-c",
            "copy",
            str(partial),
        ],
        check=True,
    )
    os.replace(partial, path)


def ts(seconds):
    seconds = round(seconds, 1)
    return f"{int(seconds // 60):02d}:{seconds % 60:04.1f}"


def main():
    done_path = STATE_DIR / ("planned.txt" if DRY_RUN else "cut.txt")
    done = set(done_path.read_text().splitlines()) if done_path.exists() else set()
    for show, sting in STINGS.items():
        for path in sorted((PODCAST_DIR / show).iterdir()):
            relative = str(path.relative_to(PODCAST_DIR))
            if (
                path.suffix.lower() not in AUDIO_SUFFIXES
                or path.name.startswith(".")
                or relative in done
            ):
                continue
            if time.time() - path.stat().st_mtime < MIN_AGE_SECONDS:
                continue
            episode, duration = fingerprint(path)
            stings = find_stings(episode, sting)
            cuts = plan_cuts(stings, duration)
            removed = sum(end - start for start, end in cuts)
            print(
                f"{relative}: stings {', '.join(map(ts, stings)) or 'none'}; cut {', '.join(f'{ts(s)}-{ts(e)}' for s, e in cuts) or 'nothing'} ({removed:.0f}s)",
                flush=True,
            )
            if cuts and not DRY_RUN:
                cut(path, cuts)
            with done_path.open("a") as f:
                f.write(relative + "\n")


if __name__ == "__main__":
    main()
