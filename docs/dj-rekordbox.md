# Rekordbox USB exports on Linux

The DJ master library is `/var/lib/media/dj` on `mlab` (AIFF from Bandcamp,
tagged by `dj-enrich`). CDJs do not read a plain folder: a Rekordbox-prepared
stick needs both databases and the analysis files at its root:

```
PIONEER/rekordbox/exportLibrary.db   OneLibrary / Device Library Plus (newer CDJs)
PIONEER/rekordbox/export.pdb         legacy database (older CDJ/XDJ)
PIONEER/USBANLZ/...                  BPM, key and waveform analysis
dj/<Artist>/<Album>/<file>           audio
```

The databases store each track's path relative to the stick root, so the
export is built in a folder with exactly that layout:
`/var/lib/media/dj-stick`. Its `dj/` is a read-only bind mount of
`/var/lib/media/dj`, so tracks are referenced in place and the exporter cannot
change the music.

It uses [djsync](https://github.com/Pikkol0/djsync) as a Python library for the
Rekordbox databases and for local BPM/key/waveform analysis. It is packaged in
`packages/djsync`; the exporter itself is `packages/dj-rekordbox`.

## Service

`hosts/mlab/dj-rekordbox.nix` runs:

```sh
dj-rekordbox export \
  --source /var/lib/media/dj-stick/dj \
  --root /var/lib/media/dj-stick \
  --min-age 120 --prune
```

- oneshot, root, every 30 minutes and 10 minutes after boot;
- the first run analyses every track (can take a long time), later runs only
  process files whose size or mtime changed;
- tracks that need analysis are analysed ahead by up to 4 worker processes
  (djsync's analysis pool, `DJSYNC_ANALYSIS_WORKERS` lowers it); database
  writes stay in one process, in order;
- files newer than 120 s are skipped so Bandcamp/Syncthing half-written files
  are not imported;
- tracks deleted from `/var/lib/media/dj` are removed from the databases; the
  exporter never moves, renames or deletes audio in place.

Before the first run it moves an export left in `/var/lib/media/dj` by the
earlier in-place layout into `/var/lib/media/dj-stick`. The exporter then
relinks those tracks to `/dj/...` and keeps their analysis.

Syncthing sends two folders to the laptop:

- `dj-library`: `/var/lib/media/dj` to `~/Music/dj`, the music;
- `dj-rekordbox`: `/var/lib/media/dj-stick/PIONEER` to `~/Music/dj-rekordbox`,
  the databases and analysis.

## Status page

<https://djexport.marcel.cool> (Authelia, `group:admins`) shows whether the
library is ready to copy. It is served by `dj-rekordbox-status` and combines:

- the export's progress file, `/var/lib/dj-rekordbox/progress.json`;
- the `dj-rekordbox` service and timer state from systemd;
- Syncthing's REST API for both folders and the laptop device.

It shows **Ready to copy** only when:

- the last export finished cleanly;
- Syncthing has scanned `dj-rekordbox` since the export finished;
- the laptop is connected and has everything in both folders.

After each export the service asks Syncthing to rescan `dj-rekordbox`, so this
does not wait for the hourly full scan.

## Making a stick

The stick must be **FAT32** (MBR, one partition) for basically all CDJs.
exFAT is only read by newer CDJ-2000NXS2/XDJ models; older players show
`NO USB` / `E-8307 DEVICE NO RESPONSE` for exFAT or NTFS. Format it once
(replace `/dev/sdX` with the whole stick, not a partition):

```sh
sudo mkfs.vfat -F 32 -n FIESTA /dev/sdX
```

Only `/dj` and `/PIONEER` on the stick belong to the export. Everything else on
it is left alone.

### Automatic copy on the laptop

Plug in a FAT32 stick labelled `FIESTA` and a notification offers **Replace with
DJ library**. A udev rule in `nixos/configuration.nix` starts the
`dj-stick@<partition>` user service from `home/dj-stick.nix`.

Clicking the button:

- refuses while an export runs on mlab or Syncthing is still receiving files;
- mounts the stick, checks it is FAT32 and that the library fits;
- makes `/dj` an exact copy of `~/Music/dj` and `/PIONEER` an exact copy of
  `~/Music/dj-rekordbox`, with a progress bar in the notification;
- unmounts and powers off the stick, then says it is safe to unplug.

Run it by hand with `dj-stick sdb1`, or `dj-stick --yes sdb1` to skip the
question.

### From mlab

```sh
dj-rekordbox sync-usb --root /var/lib/media/dj-stick \
  --dest /run/media/$USER/FIESTA --delete
```

`sync-usb`:

- refuses a destination that already contains a Rekordbox library unless it has
  the `.dj-rekordbox-export` marker (or `--force` is given);
- rejects NTFS/ext4 and warns about exFAT;
- checks free space (64 MiB margin);
- uses rsync so repeated copies are incremental, and `--delete` never removes
  top-level folders that are not part of the export;
- writes the marker only after a successful copy.

`DJSync_Backups/` is deliberately not copied.

## Manual commands

```sh
dj-rekordbox init   --root /tmp/cdj-test
dj-rekordbox export --source /path/to/dj --root /tmp/cdj-test --min-age 0 -v
dj-rekordbox status --root /tmp/cdj-test
dj-rekordbox sync-usb --root /tmp/cdj-test --dest /run/media/$USER/FIESTA --delete
```

`status` prints track/playlist counts and whether the legacy `export.pdb` is
in sync. `export --dry-run` requires an existing export and only reports what
would change.

## What about other tools?

- **pyrekordbox / rbox** manage the desktop Rekordbox `master.db`, not a CDJ
  stick, so they are not a drop-in USB exporter.
- **openboxxx** is a beta that writes only `export.pdb`; it was not confirmed
  on real CDJ hardware.
- **Rekordbox under Wine** works for the GUI, but is fragile and not
  scriptable/headless.

## Limitations

- OGG/Opus/WMA/MP4/M4A and similar files are skipped with a warning; CDJs do not
  play them from a Rekordbox stick. AIFF, FLAC, MP3, WAV and M4A (AAC) are the
  useful formats.
- Tracks longer than 30 minutes (gapless albums, mixes) are skipped and removed
  from the export; change the limit with `--max-duration`, `0` turns it off.
- Analysis is done on `mlab` (numpy + ffmpeg), not by Rekordbox. BPM/key values
  can differ slightly from Rekordbox's own analyser.
- Genre playlists are written under a top-level `DJSync` folder (`Genres/<genre>`).
- Always test a new stick on the actual player before a gig.
