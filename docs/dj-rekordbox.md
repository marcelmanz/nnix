# Rekordbox USB exports on Linux

The DJ master library is `/var/lib/media/dj` on `mlab` (AIFF from Bandcamp,
tagged by `dj-enrich`). CDJs do not read a plain folder: a Rekordbox-prepared
stick needs both databases and the analysis files:

```
PIONEER/rekordbox/exportLibrary.db   OneLibrary / Device Library Plus (newer CDJs)
PIONEER/rekordbox/export.pdb         legacy database (older CDJ/XDJ)
PIONEER/USBANLZ/...                  BPM, key and waveform analysis
Contents/<Artist>/<Album>/<file>     audio
```

`dj-rekordbox` maintains that layout on `mlab` and copies it to a USB stick.
It uses [djsync](https://github.com/Pikkol0/djsync) as a Python library for the
Rekordbox databases and for local BPM/key/waveform analysis. It is packaged in
`packages/djsync`; the exporter itself is `packages/dj-rekordbox`.

## Service

`hosts/mlab/dj-rekordbox.nix` runs:

```sh
dj-rekordbox export \
  --source /var/lib/media/dj \
  --root /var/lib/media/dj-rekordbox \
  --min-age 120 --prune
```

- oneshot, root, every 30 minutes and 10 minutes after boot;
- the first run analyses every track (can take a long time), later runs only
  process files whose size or mtime changed;
- files newer than 120 s are skipped so Bandcamp/Syncthing half-written files
  are not imported;
- tracks deleted from `/var/lib/media/dj` are removed from the export and the
  databases.

The export root is `/var/lib/media/dj-rekordbox`. It is a complete stick image;
do not point CDJs at `/var/lib/media/dj` directly.

## Making a stick

The stick must be **FAT32** (MBR, one partition) for basically all CDJs.
exFAT is only read by newer CDJ-2000NXS2/XDJ models; older players show
`NO USB` / `E-8307 DEVICE NO RESPONSE` for exFAT or NTFS.

```sh
# format once (replace /dev/sdX with the whole stick, not a partition)
sudo mkfs.vfat -F 32 -n CDJ /dev/sdX

# mount it, then copy the prepared export
dj-rekordbox sync-usb --root /var/lib/media/dj-rekordbox \
  --dest /run/media/$USER/CDJ --delete
```

`sync-usb`:

- refuses a destination that already contains a Rekordbox library unless it has
  the `.dj-rekordbox-export` marker (or `--force` is given);
- rejects NTFS/ext4 and warns about exFAT;
- checks free space (64 MiB margin);
- uses rsync so repeated copies are incremental;
- writes the marker only after a successful copy.

Use the whole prepared export, including `PIONEER/` **and** `Contents/`.
`DJSync_Backups/` is deliberately not copied.

## Manual commands

```sh
dj-rekordbox init   --root /tmp/cdj-test
dj-rekordbox export --source /path/to/dj --root /tmp/cdj-test --min-age 0 -v
dj-rekordbox status --root /tmp/cdj-test
dj-rekordbox sync-usb --root /tmp/cdj-test --dest /run/media/$USER/CDJ --delete
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
- Analysis is done on `mlab` (numpy + ffmpeg), not by Rekordbox. BPM/key values
  can differ slightly from Rekordbox's own analyser.
- Genre playlists are written under a top-level `DJSync` folder (`Genres/<genre>`).
- Always test a new stick on the actual player before a gig.
