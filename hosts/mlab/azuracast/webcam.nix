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

      paths.webcam = {
        # -c:v libx264 is required, not cosmetic: ffmpeg's RTSP default encoder is MPEG-4 Part 2,
        # which isn't in WebRTC's codec list (H264/H265/VP8/VP9/AV1). ultrafast/zerolatency keep
        # the encoder fast enough for real-time capture.

        # -g/-keyint_min force a keyframe every 30 frames (~1s): this is a plain RTSP push, not
        # a live WebRTC publish, so mediamtx has no PLI path back to ffmpeg to request a keyframe
        # for a newly joining viewer - without a short GOP they wait for libx264's default
        # (~250 frames, i.e. up to several seconds of black screen depending on join timing).

        # The -vf value is read fresh from effect file on every (re)start; webcam-control.py
        # writes the chosen filter there and restarts mediamtx to apply it.
        # Must be a script file, not an inline shell one-liner: mediamtx fork/execs runOnInit
        # directly (no shell), so "filter=$(...)" isn't parsed - it's treated as the program name.
        runOnInit = pkgs.writeShellScript "webcam-publish" ''
          filter="$(cat /var/lib/webcam-control/effect 2>/dev/null)"
          exec ${lib.getExe pkgs.ffmpeg} -f v4l2 -i /dev/video0 -an -vf "''${filter:-null}" -c:v libx264 -preset ultrafast -tune zerolatency -g 30 -keyint_min 30 -pix_fmt yuv420p -f rtsp rtsp://localhost:$RTSP_PORT/$RTSP_PATH
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

  # lets the control page apply a new -vf effect by restarting mediamtx (see webcam-control.py).
  security.sudo.extraRules = [
    {
      users = ["webcam-control"];
      commands = [
        {
          command = "/run/current-system/sw/bin/systemctl restart mediamtx";
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
