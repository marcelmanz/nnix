{
  config,
  pkgs,
  lib,
  services,
  ...
}: {
  services.mediamtx = {
    enable = true;
    allowVideoAccess = true; # grants the "video" group so /dev/video0 is readable
    settings = {
      # WebRTC only - rtsp stays on (internal-only, used by the ffmpeg push below); hls/rtmp are
      # unused and hls's default port collides with an existing container on this host.
      hls = false;
      rtmp = false;
      webrtcAdditionalHosts = ["radio.marcel.cool"];
      webrtcAddress = "127.0.0.1:8889";

      # HTTP auth, not IP-based rules: the toggle in webcam-control.py needs to gate the actual
      # stream, not just whether the public page's JS bothers to show it. Every read/publish
      # attempt asks /authcheck; see webcam-control.py for the logic.
      authMethod = "http";
      authHTTPAddress = "http://127.0.0.1:${toString services.streamcam.port}/authcheck";

      # Audio-only path published by azuracast-live-monitor (live.nix): the desk mix as
      # Opus, read over WebRTC from the LAN-only player on 192.168.1.140:8091. No public
      # nginx location proxies it, and webrtcAddress is loopback, so LAN is the only way in.
      paths.livemix = {};

      paths.webcam = {
        # H.264 is required, not cosmetic: ffmpeg's RTSP default encoder is MPEG-4 Part 2,
        # which isn't in WebRTC's codec list (H264/H265/VP8/VP9/AV1).

        # h264_vaapi, not libx264: at 1080p60 the iGPU encodes this for ~0.55 of a core where
        # libx264 -preset ultrafast needs ~0.93 and looks markedly worse (measured SSIM against
        # the camera's own MJPEG: 0.961 vaapi vs 0.947 ultrafast, and vaapi does it at 3.9Mbit/s
        # vs 4.6). ultrafast was always this soft - it drops CABAC and 8x8 transform, which is
        # why it can't hold 1080p at this bitrate. Raising the cap doesn't fix it either:
        # ultrafast at 12M still only reaches 0.954. This ffmpeg has no QSV
        # (--disable-libmfx/--disable-libvpl), so VAAPI is the way onto the same iGPU.

        # scale=in_range=pc:out_range=tv is load-bearing too: the BRIO's MJPEG is yuvj422p
        # (full range) and a bare format=nv12 keeps that range, so the encoder emitted a
        # full-range stream (ffprobe: pix_fmt=yuvj420p, color_range=pc). WebRTC decoders render
        # H.264 as limited range regardless of the VUI flag, so full-range pixels came out
        # washed out - which is what "lower quality since the vaapi switch" actually was.
        # libx264 never showed it: -pix_fmt yuv420p did this conversion implicitly.

        # hqdn3d denoises BEFORE the encoder, which is the only thing that actually removed the
        # grain: raising the bitrate cap made it worse, not better (8M reproduces the camera's
        # own noise more faithfully - measured frame-to-frame difference 0.592 vs 0.546 at 6M,
        # while hqdn3d at 6M gives 0.400). CPU filter, so it runs before hwupload: ~+0.5 of a
        # core (0.67 -> 1.16 total), still 2.1x realtime at 1080p60. 3:2:6:6 is the strength
        # knob - 2:1.5:4:4 if it ever looks smeared.

        # -bf 0 is load-bearing: vaapi emits B-frames by default and WebRTC decoders choke on
        # them. Note this moves the stream from Constrained Baseline to High profile - any
        # encoder better than ultrafast does. If a browser ever refuses to play it, going back
        # is -c:v libx264 -preset veryfast -tune zerolatency (same quality, ~2 cores).

        # -g forces a keyframe every 60 frames (~1s): this is a plain RTSP push, not
        # a live WebRTC publish, so mediamtx has no PLI path back to ffmpeg to request a keyframe
        # for a newly joining viewer - without a short GOP they wait for libx264's default
        # (~250 frames, i.e. up to several seconds of black screen depending on join timing).

        # The -vf value is read fresh from effect file on every (re)start; webcam-control.py
        # writes the chosen filter there and restarts mediamtx to apply it.
        # Must be a script file, not an inline shell one-liner: mediamtx fork/execs runOnInit
        # directly (no shell), so "filter=$(...)" isn't parsed - it's treated as the program name.
        runOnInit = pkgs.writeShellScript "webcam-publish" ''
          filter="$(cat /var/lib/webcam-control/effect 2>/dev/null)"
          # All three of -input_format/-video_size/-framerate are required. With none of them
          # ffmpeg takes the driver's default, which is the first entry of the first format:
          # YUYV 640x480. -input_format mjpeg is what buys the 60 specifically - the BRIO's
          # YUYV and NV12 modes stop at 1080p30, only MJPG goes to 1080p60 (and 1440p30/
          # 2160p30). Note the camera advertises none of this below SuperSpeed: on a USB 2.0
          # port it caps at 1080p, and YUYV 1080p there is 5fps.
          #
          # 1080p60 over 2160p30 on purpose - a DJ cam is mostly motion, and this is a WebRTC
          # webcam, so every extra pixel is paid for by every viewer (4K measures 16Mbit/s
          # each, vs 5) and by azuracast-live-record, which stream-copies whatever's here.

          # -maxrate/-bufsize: libx264 at -preset ultrafast is bitrate-hungry and there was no
          # cap while this was 640x480. At 1080p60 an uncapped ultrafast stream runs into
          # double digit Mbit/s - too much for viewers and for azuracast-live-record, which
          # stream-copies this. 6M measures at 4.96Mbit/s actual, ~2.7GB/h recorded.

          # by-id (serial-pinned), not /dev/video0: device numbering shifts whenever any
          # UVC device is (un)plugged or on boot order changes.
          exec ${lib.getExe pkgs.ffmpeg} -f v4l2 -input_format mjpeg -video_size 1920x1080 -framerate 60 -i /dev/v4l/by-id/usb-046d_Logitech_BRIO_F67E04C5-video-index0 -an -vaapi_device /dev/dri/renderD128 -vf "''${filter:-null},hqdn3d=3:2:6:6,scale=in_range=pc:out_range=tv,format=nv12,hwupload" -c:v h264_vaapi -b:v 6M -maxrate 6M -bf 0 -g 60 -f rtsp rtsp://localhost:$RTSP_PORT/$RTSP_PATH
        '';
        runOnInitRestart = true;
      };
    };
  };
  networking.firewall.allowedUDPPorts = [8189];

  # services.mediamtx writes its config via pkgs.formats.yaml, which prepends a
  # "%YAML 1.1\n---\n" header that MediaMTX's own parser rejects. Strip those first two lines.
  environment.etc."mediamtx.yaml".source = lib.mkForce (
    pkgs.runCommand "mediamtx.yaml" {} ''
      tail -n +3 ${(pkgs.formats.yaml {}).generate "mediamtx.yaml" config.services.mediamtx.settings} > $out
    ''
  );

  # Private preview + "go live" switch (Authelia-gated, see proxy.nix/authelia.nix). The public
  # page polls radio.marcel.cool/webcam-status before ever showing the video element.
  users.users.webcam-control = {
    isSystemUser = true;
    group = "webcam-control";
  };
  users.groups.webcam-control = {};

  # lets the control page apply a new -vf effect by restarting the publisher above
  # (see webcam-control.py). sudo matches the whole command line, so this string has to
  # stay byte-identical to the one webcam-control.py runs.
  security.sudo.extraRules = [
    {
      users = ["webcam-control"];
      commands = [
        {
          command = "/run/current-system/sw/bin/pkill -f usb-046d_Logitech_BRIO_F67E04C5";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];

  # mediamtx calls webcam-control-web for every read/publish auth check, so it must be up first.
  systemd.services.mediamtx = {
    after = ["webcam-control-web.service"];
    wants = ["webcam-control-web.service"];
  };

  systemd.services.webcam-control-web = {
    description = "Webcam preview + public-visibility toggle";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "simple";
      User = "webcam-control";
      StateDirectory = "webcam-control";
      ExecStart = "${pkgs.python3}/bin/python3 ${./webcam-control.py} ${toString services.streamcam.port} /var/lib/webcam-control/live";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
