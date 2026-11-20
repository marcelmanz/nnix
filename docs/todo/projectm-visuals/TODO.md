# TODO

- [ ] Build gst-plugins-bad with the projectm element
  - [ ] Override gst-plugins-bad locally in visuals.nix, adding libprojectm to
        buildInputs and projectm enabled to mesonFlags
  - [ ] Confirm gst-inspect-1.0 projectm lists the element

- [ ] Fetch the projectM presets
  - [ ] Add presets-cream-of-the-crop from projectM-visualizer with
        fetchFromGitHub
  - [ ] Decide whether a curated subset is needed to hold 30fps

- [ ] Prove the pipeline by hand on mlab
  - [ ] Pick the headless GL platform, surfaceless or gbm, on renderD128
  - [ ] Render radio.mp3 through projectm at 1080p30 into a file
  - [ ] Encode with vah264enc, no B-frames, keyframe every 30 frames
  - [ ] Mux AAC 160k audio from the same decode
  - [ ] Measure CPU and iGPU load
  - [ ] Fall back to libprojectm plus ffmpeg h264_vaapi if the element or VA
        encoder does not work

- [ ] Publish the visuals mediamtx path
  - [ ] Create hosts/mlab/azuracast/visuals.nix with paths.visuals,
        runOnDemand as a writeShellScript that execs gst-launch-1.0
  - [ ] Set runOnDemandRestart
  - [ ] Set GST_PLUGIN_SYSTEM_PATH_1_0 and the GST_GL env for headless EGL
  - [ ] Give the mediamtx service access to the render group
  - [ ] Import visuals.nix from hosts/mlab/azuracast/default.nix

- [ ] Allow public reads of visuals in authcheck
  - [ ] Add a visuals exception next to livemix in webcam-control.py

- [ ] Verify on mlab
  - [ ] Play rtsp://127.0.0.1:8554/visuals with mpv and check audio and video
        sync
  - [ ] Check the publisher stops after the last reader leaves

- [ ] Play the visuals on the Xiaomi box
  - [ ] Add hosts/mlab/radio-local/visuals.m3u pointing at the LAN RTSP path
  - [ ] Serve visuals.m3u with the audio/x-mpegurl type in radioLanLocations
        in proxy.nix
  - [ ] Open it in mpv-android on the box

- [ ] Add visuals to resona
  - [ ] Proxy /visuals-hls/ to mediamtx HLS in module.nix, mirroring
        /webcam-av-hls/
  - [ ] Note in the module comment that the host also publishes visuals
  - [ ] Make startVideo in video.js take the stream URL
  - [ ] Add a Visuals toggle on the stage in index.html and player.js, shown
        only while not live
  - [ ] Keep the webcam winning while live, and go back to visuals after the
        show if the toggle was on
  - [ ] Fall back to now-playing polling while in visuals mode
  - [ ] Test with dev.py

- [ ] Ship resona
  - [ ] Push resona and run nix flake update resona
  - [ ] Rebuild mlab and test radio.marcel.cool off the LAN on mobile data

- [ ] Phase 2, only once everything above works: overlay visuals on the webcam
  - [ ] Add a webcamvisuals path that composites projectm rendered from
        livemix over the webcam and muxes livemix audio
  - [ ] Let resona choose between webcamav and webcamvisuals while live

- [ ] Phase 3, after phase 2: pick presets from the live deck
  - [ ] Check whether the projectm element can switch preset at runtime
  - [ ] Replace gst-launch-1.0 with a controller that sets the preset live,
        or restart the publisher like the webcam effect as a first cut
  - [ ] Add a preset action and the preset list to state in
        webcam-control.py, mirroring the effect action
  - [ ] Add a preset picker with next, previous and auto to the
        live.marcel.cool deck in live-toggle.py
