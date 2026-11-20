# Plan: projectM Visuals for Radio Marcel

## Goal

Render projectM (MilkDrop) visuals on mlab from the AzuraCast broadcast and
publish them as one stream with the radio audio muxed in. Muxing is what keeps
the visuals on the beat for every viewer.

The stream is a new mediamtx path, `visuals`, published on demand the same way
`webcam` and resona's `webcamav` are. It renders only while someone watches.

Two consumers: the Xiaomi TV box (mpv-android, over LAN RTSP) and
radio.marcel.cool (resona, over LL-HLS through hls.js). Output is 1080p30
H.264 on the iGPU plus AAC audio.

During a live show resona keeps showing the webcam exactly as now. Overlaying
the visuals on the webcam is phase 2, started only once phase 1 works.

---

## Stream contract

| Path | Publisher | Video | Audio | Read access |
| ---- | --------- | ----- | ----- | ----------- |
| `visuals` | mlab `visuals-publish` (runOnDemand) | H.264 1080p30, `-bf 0`, GOP 30 | AAC 160k, from `radio.mp3` | always (public radio) |
| `webcam` | unchanged | | | unchanged |
| `webcamav` | unchanged (resona) | | | unchanged |

Endpoints:

| Who | URL |
| --- | --- |
| Xiaomi box (LAN) | `rtsp://192.168.1.140:8554/visuals`, via `visuals.m3u` |
| radio.marcel.cool | `/visuals-hls/index.m3u8` (nginx to mediamtx HLS `127.0.0.1:8890/visuals/`) |

The box uses RTSP rather than HLS: it is already LAN-only on 8554
(`webcam.nix` firewall rules), it has lower latency and needs no TLS.

Pipeline (single GStreamer process, so audio and video share one clock):

```
souphttpsrc http://127.0.0.1:<azuracast>/listen/radio_marcel/radio.mp3 is-live=true
  ! decodebin ! audioconvert ! audioresample ! tee name=t
t. ! queue ! projectm preset=<dir> preset-duration=<s> mesh-size=...
   ! video/x-raw(memory:GLMemory),width=1920,height=1080,framerate=30/1
   ! gldownload ! videoconvert ! vapostproc ! vah264enc bitrate=6000
     key-int-max=30 b-frames=0 ! h264parse ! sink.
t. ! queue ! avenc_aac bitrate=160000 ! aacparse ! sink.
rtspclientsink name=sink location=rtsp://127.0.0.1:$RTSP_PORT/$RTSP_PATH protocols=tcp
```

Headless GL: `GST_GL_PLATFORM=egl`, `GST_GL_WINDOW=surfaceless` (or `gbm`) on
`/dev/dri/renderD128`. No compositor or X server.

---

## Files to create / modify

### Phase 1: visuals stream, box and resona

1. `hosts/mlab/azuracast/visuals.nix` (NEW)
   - `gstBadProjectm`: `pkgs.gst_all_1.gst-plugins-bad.overrideAttrs` adding
     `libprojectm` to `buildInputs` and `-Dprojectm=enabled` to `mesonFlags`.
     Local to this file, not a flake overlay, so nothing else rebuilds against
     it.
   - `projectmPresets`: `fetchFromGitHub` of
     `projectM-visualizer/presets-cream-of-the-crop` (no preset package in
     nixpkgs).
   - `services.mediamtx.settings.paths.visuals` with `runOnDemand` as a
     `writeShellScript` (mediamtx execs without a shell, see `webcam.nix`)
     that `exec`s `gst-launch-1.0` with the pipeline above, and
     `runOnDemandRestart = true`.
   - `GST_PLUGIN_SYSTEM_PATH_1_0` built from base, good, `gstBadProjectm`,
     libav, and the VA plugins; `GST_GL_*` env for headless EGL.
   - Ensure mediamtx can open `/dev/dri/renderD128` (add the `render` group
     to the mediamtx service, alongside `allowVideoAccess`).
2. `hosts/mlab/azuracast/default.nix` (MODIFY)
   - Add `./visuals.nix` to `imports`.
3. `hosts/mlab/azuracast/webcam-control.py` (MODIFY)
   - In `/authcheck`, allow every read on path `visuals`, like `livemix`. It
     carries only the public broadcast, so it is not gated on the go-live
     toggle.
4. `hosts/mlab/radio-local/visuals.m3u` (NEW)
   - `#EXTM3U` playlist pointing at `rtsp://192.168.1.140:8554/visuals`,
     same shape as `desk.m3u`.
5. `hosts/mlab/proxy.nix` (MODIFY)
   - `"= /visuals.m3u"` in `radioLanLocations` with
     `default_type audio/x-mpegurl;`, like `/desk.m3u`.
6. resona `module.nix` (MODIFY, `~/clones/own/resona`)
   - `"/visuals-hls/"` location proxying to
     `${hlsAddress}/visuals/`, with `limit_conn resona_video`,
     `proxy_buffering off` and `proxy_redirect /visuals/ /visuals-hls/`,
     mirroring `/webcam-av-hls/`.
   - Update the header comment: the host is also expected to publish
     `visuals`.
7. resona `web/video.js` (MODIFY)
   - Make the stream URL a parameter of `startVideo(url)` so the same
     element and hls.js setup play either `webcamav` or `visuals`.
8. resona `web/player.js` and `web/index.html` (MODIFY)
   - A "Visuals" toggle on the stage, shown only while not live.
   - On: `stopRadio()`, show `#video`, `startVideo("/visuals-hls/...")`.
     Off: back to the mp3 radio.
   - `setLive(true)` overrides it: the webcam wins while on air, as now.
     When the show ends, return to visuals if the toggle was on.
9. resona `web/nowplaying.js` (MODIFY, if needed)
   - In visuals mode the `songchange` ICY events from `radio.js` stop. Fall
     back to `pollNowPlaying` / the SSE follower, and accept the ~3s HLS
     offset in the track title.
10. `flake.lock` (MODIFY)
    - `nix flake update resona` once resona is pushed.

### Phase 2: visuals overlaid on the webcam (later)

11. `hosts/mlab/azuracast/visuals.nix` (MODIFY)
    - A second path, e.g. `webcamvisuals`, that takes `webcam` (RTSP) plus
      projectM rendered from `livemix` (the desk audio, ahead of the
      broadcast), composites with `glvideomixer` or `compositor` (projectM
      with alpha or a blend mode over the camera) and muxes `livemix` as AAC.
12. resona `web/player.js` (MODIFY)
    - While live, a choice between `webcamav` and `webcamvisuals`.

### Phase 3: preset selection from the live deck (later)

13. `hosts/mlab/azuracast/live-toggle.py` (MODIFY)
    - A preset picker on the live.marcel.cool deck, next to the webcam
      effect `<select>`: pick a preset, next/previous, or back to auto
      cycling.
14. `hosts/mlab/azuracast/webcam-control.py` (MODIFY)
    - A `/preset` action that stores the choice and the preset list in
      `/state`, mirroring `/effect`.
15. `hosts/mlab/azuracast/visuals.nix` (MODIFY)
    - Make the renderer take the preset without dropping viewers. Either a
      long-running controller (Python GStreamer app with a control socket
      that sets the `projectm` element's properties live) in place of
      `gst-launch-1.0`, or the `/effect` style restart as a first cut.

---

## Order of work

1. Build `gstBadProjectm` alone and confirm `gst-inspect-1.0 projectm` lists
   the element.
2. Run the pipeline by hand on mlab into `filesink` or `autovideosink`, to
   prove headless EGL, preset loading and VA encoding at 1080p30. Measure CPU
   and GPU.
3. `visuals.nix` with the mediamtx path, plus the `default.nix` import.
4. `/authcheck` exception in `webcam-control.py`.
5. Rebuild mlab and play `rtsp://127.0.0.1:8554/visuals` with mpv. Check
   audio and video sync and that the publisher stops when the last reader
   leaves.
6. `visuals.m3u` plus the `proxy.nix` location. Open it on the Xiaomi box in
   mpv-android.
7. resona: nginx location, `video.js` URL parameter, toggle in
   `player.js`/`index.html`, now-playing fallback. Test with resona's
   `dev.py`.
8. Push resona, `nix flake update resona`, rebuild, and test
   radio.marcel.cool off-LAN (phone on mobile data).
9. Phase 2, only after 1-8 are stable.
10. Phase 3, after phase 2.

---

## Open questions / assumptions

- **gstprojectm build**: assumed that adding `libprojectm` 4.1.8 to
  gst-plugins-bad 1.28.8 is enough (meson `projectm` is `auto` and not in the
  nixpkgs disabled list). If the element is missing or broken, fall back to a
  small C program on libprojectm + EGL surfaceless, piping raw frames into the
  same ffmpeg VAAPI command as `webcam.nix`.
- **VA in GStreamer**: assumed `vah264enc` (gst-plugins-bad `va`) works on
  the iGPU with `intel-media-driver`. Fallback: pipe raw video to ffmpeg
  `h264_vaapi`, already proven in `webcam.nix`.
- **Headless GL platform**: `surfaceless` versus `gbm` is untested. Settle it
  in step 2.
- **Presets**: cream-of-the-crop is about 9k presets, and some are heavy.
  May need a curated subset, or `preset-duration` plus hard-cut settings, to
  hold 30fps on the iGPU.
- **Audio source**: `radio.mp3` (192k MP3, re-encoded to AAC) is the
  broadcast exactly as listeners get it, live shows included. During a show
  resona shows the webcam anyway, so the broadcast's ~16s lag behind the desk
  does not matter for phase 1.
- **Read access**: `visuals` is public with no toggle. `limit_conn
  resona_video 10` and on-demand publishing bound the cost. Revisit if mlab
  load becomes an issue.
- **Xiaomi box launch**: phase 1 is the `.m3u` opened in mpv-android. A Home
  Assistant button that launches it via `androidtv_remote` (deep link) is
  optional and not planned yet.
- **Now-playing in visuals mode** loses the exact ICY song-change timing.
  Assumed acceptable. mediamtx does not carry ICY metadata.
- **Phase 2 audio**: overlay visuals should react to `livemix` (the desk),
  not the delayed broadcast, so they match the webcam. Confirm then.
- **Phase 3 preset switching**: the `/effect` pattern restarts the publisher,
  which stalls every viewer and splits the live recording. Live switching
  needs the controller process. Check whether `gstprojectm` exposes a
  property for loading a single preset at runtime, or only a preset dir.
- **Phase 3 scope**: assumed the picker drives the live overlay
  (`webcamvisuals`) and, if cheap, the off-air `visuals` stream too.
