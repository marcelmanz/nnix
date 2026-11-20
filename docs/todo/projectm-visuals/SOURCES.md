# Sources: projectM Visuals for Radio Marcel

| Source | What it gives us |
| ------ | ---------------- |
| `hosts/mlab/azuracast/webcam.nix:79-111` | `paths.webcam` `runOnDemand` `writeShellScript` + `runOnDemandRestart` pattern, h264_vaapi flags (`-bf 0`, short GOP) and why |
| `hosts/mlab/azuracast/webcam.nix:8-37` | mediamtx settings: LL-HLS on `127.0.0.1:8890`, HTTP `authMethod`, `paths.livemix` |
| `hosts/mlab/azuracast/webcam.nix:135-139` | `mediamtx.yaml` header-strip workaround the new path inherits |
| `hosts/mlab/azuracast/webcam.nix:165` | `systemd.services.mediamtx` override, where render-group access goes |
| `~/clones/own/resona/module.nix:28-39` | `webcamav` muxed path: the "separate players drift" rationale and AAC 160k |
| `~/clones/own/resona/module.nix:68-75` | `/webcam-av-hls/` nginx location to mirror for `/visuals-hls/` |
| `~/clones/own/resona/web/video.js:4,30-50` | hard-coded `VIDEO_URL` and hls.js `startVideo` to parametrise |
| `~/clones/own/resona/web/player.js:55-88` | `setLive` / `pollLive` webcam switching the visuals toggle must yield to |
| `~/clones/own/resona/web/radio.js:95-133` | ICY `songchange` events that stop in visuals mode |
| `~/clones/own/resona/web/nowplaying.js:93-122` | `songchange` handler and `pollNowPlaying` fallback |
| `~/clones/own/resona/web/index.html:32-37` | `#stage` with `#video`, `#cover`, `#toggle` where the Visuals button goes |
| `hosts/mlab/azuracast/webcam-control.py:184-222` | `/authcheck` read rules and the `livemix` exception to copy for `visuals` |
| `hosts/mlab/azuracast/webcam-control.py:131-160` | `/effect` action: state file plus publisher restart, the phase 3 preset pattern and its viewer-drop caveat |
| `hosts/mlab/azuracast/live-toggle.py:222-225,269-275` | live deck effect `<select>` to mirror for the preset picker |
| `hosts/mlab/azuracast/default.nix:7` | `imports` list for `./visuals.nix` |
| `hosts/mlab/azuracast/default.nix:156-160` | `services.resona` enabled on `radio.marcel.cool` |
| `hosts/mlab/azuracast/live.nix:210-238` | desk `livemix` Opus publisher and the ~16s broadcast lag (phase 2 audio source) |
| `hosts/mlab/proxy.nix:318-345` | `radioLanLocations` and `/desk.m3u` mime-type location to copy |
| `hosts/mlab/radio-local/desk.m3u` | LAN RTSP playlist shape for `visuals.m3u` |
| `hosts/mlab/proxy.nix:694-706` | AzuraCast `radio.mp3` mount, the audio source |
| `hosts/mlab/default.nix:237-244` | iGPU `hardware.graphics` with intel-media-driver for VA |
| nixpkgs `pkgs/development/libraries/gstreamer/bad/default.nix:280-345` | gst-plugins-bad `mesonFlags`: `projectm` not disabled, `libprojectm` not a dependency |
| nixpkgs `libprojectm` 4.1.8, `projectm-sdl-cpp` | available projectM packages, no preset package |
