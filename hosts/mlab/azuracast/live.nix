{
  config,
  pkgs,
  services,
  ...
}: {
  sops.secrets."azuracast_dj_password" = {};

  # snd-aloop: a virtual sound card whose device 0 and device 1 are cross-wired - whatever's
  # played into device 0's playback appears on device 1's capture. Used below to hand darkice a
  # single "device" that's actually the mix of the Scarlett 2i2 + the USB mic, without touching
  # darkice's (already-secure) Icecast leg at all.
  boot.kernelModules = ["snd-aloop"];

  # Mixes the Scarlett 2i2 (card USB) and the Amazon USB mic (card Mic) and plays the result into
  # the loopback card's device 0 - azuracast-live-capture below reads it back from device 1.
  # aresample=async=1 on each leg: the two USB interfaces free-run on independent clocks, so
  # without it they'd slowly drift apart; this lets ffmpeg stretch/compress each leg a little to
  # stay in sync instead of glitching.
  systemd.services.azuracast-live-mix = {
    description = "Mix Scarlett 2i2 + USB mic into the loopback device darkice reads from";
    after = ["sound.target"];
    serviceConfig = {
      Type = "simple"; # ffmpeg's own alsa output negotiates a 128-frame (~3ms) period against Loopback's
      # 131072-frame buffer - impossible for a non-hard-realtime filter pipeline to service
      # every write, causing constant "ALSA buffer xrun" (audible glitches/dropouts). ffmpeg
      # exposes no period/buffer controls for alsa output, so the mix is piped as raw PCM into
      # aplay instead, which does - forced to the same sane period darkice's capture side gets.
      ExecStart = pkgs.writeShellScript "azuracast-live-mix" ''
        set -o pipefail
        ${pkgs.ffmpeg}/bin/ffmpeg -f alsa -ar 44100 -ac 2 -i plughw:CARD=USB \
          -f alsa -ar 44100 -ac 2 -i plughw:CARD=Mic \
          -filter_complex '[0:a]aresample=async=1:first_pts=0[a0];[1:a]aresample=async=1:first_pts=0[a1];[a0][a1]amix=inputs=2:duration=first:dropout_transition=0[aout]' \
          -map '[aout]' -f s16le - \
          | ${pkgs.alsa-utils}/bin/aplay -D plughw:CARD=Loopback,DEV=0 -f S16_LE -r 44100 -c 2 \
              --buffer-time=200000 --period-time=50000
      '';
      Restart = "on-failure";
      RestartSec = "5s";
      # Real-time scheduling: without it, other ffmpeg jobs on the box (webcam relay, Jellyfin
      # thumbnailing) can delay this thread past its ALSA period and cause a dropout even with
      # the sane period above. darkice already self-requests SCHED_RR; this gives the mixer
      # feeding it the same guarantee.
      CPUSchedulingPolicy = "rr";
      CPUSchedulingPriority = 20;
    };
  };

  # Captures the Scarlett 2i2 + USB mic mix (via the loopback, see azuracast-live-mix above) and
  # pushes it into AzuraCast's DJ harbor (127.0.0.1:8005, published from the container in
  # ./default.nix). Not started at boot: an idle mixer would push dead air over the auto-DJ.
  # Toggle via https://livedj.marcel.cool or systemctl.
  systemd.services.azuracast-live-capture = {
    description = "Capture the live mix and stream it to AzuraCast";
    after = ["sound.target" "podman-azuracast.service" "azuracast-live-mix.service"];
    bindsTo = ["azuracast-live-mix.service"]; # no point encoding silence if the mixer died
    serviceConfig = {
      Type = "simple";
      RuntimeDirectory = "azuracast-live-capture";
      RuntimeDirectoryMode = "0700";
      Restart = "on-failure";
      RestartSec = "5s";
    };
    # darkice's config is a plain file, so it's generated at start into RuntimeDirectory
    # (tmpfs, root-only) with the password read from sops at runtime - never written to the
    # nix store. plughw (not hw): needed for ALSA's plugin layer for format conversion.
    # mountPoint is blank: darkice always sends "SOURCE /" + mountPoint, so "/" would send
    # "SOURCE //", which doesn't match AzuraCast's DJ mount point ("/").
    script = ''
      DJ_PASSWORD=$(cat ${config.sops.secrets.azuracast_dj_password.path})
      cat > /run/azuracast-live-capture/darkice.cfg <<EOF
      [general]
      duration = 0
      bufferSecs = 5
      reconnect = yes

      [input]
      device = plughw:CARD=Loopback,DEV=1
      sampleRate = 44100
      bitsPerSample = 16
      channel = 2

      [icecast2-0]
      bitrateMode = cbr
      format = mp3
      bitrate = 192
      server = 127.0.0.1
      port = 8005
      password = $DJ_PASSWORD
      mountPoint =
      name = Live DJ
      public = no
      EOF
      exec ${pkgs.darkice}/bin/darkice -c /run/azuracast-live-capture/darkice.cfg
    '';
  };

  # Tiny status/start-stop page for the capture service above, sat behind Authelia via
  # the `livedj` entry in proxy.nix's `services` set. Runs unprivileged; the only thing
  # it can do as root is start/stop this one unit (security.sudo.extraRules below). `audio`
  # group membership (same as /dev/snd's own group) lets it flip the mic's hardware mute
  # switch and record a test clip directly - no sudo needed for either.
  users.users.azuracast-live-web = {
    isSystemUser = true;
    group = "azuracast-live-web";
    extraGroups = ["audio"];
  };
  users.groups.azuracast-live-web = {};

  systemd.services.azuracast-live-web = {
    description = "Toggle page for the live DJ capture stream";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "simple";
      User = "azuracast-live-web";
      StateDirectory = "azuracast-live-web"; # holds the last test-mic.mp3 recording
      ExecStart = "${pkgs.python3}/bin/python3 ${./live-toggle.py} ${toString services.livedj.port} ${pkgs.alsa-utils}/bin/amixer ${pkgs.ffmpeg}/bin/ffmpeg";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  # Records the show while it's on air: the webcam's H.264 straight off mediamtx's internal RTSP
  # path, muxed live against the station's own FLAC mount. Two things this deliberately does not
  # do: it never touches the loopback darkice reads from (a second ALSA capture client on
  # cable#0 would fight darkice for it, and dsnoop in that path risks xruns on the actual
  # broadcast), and it never re-encodes video - the webcam is already H.264 for WebRTC, so
  # -c:v copy costs no CPU and can't compete with Jellyfin for the iGPU.
  #
  # bindsTo+wantedBy on the capture unit: the existing livedj.marcel.cool toggle starts and stops
  # this too, so there's one switch for the show, not two that can drift apart.
  systemd.services.azuracast-live-record = {
    description = "Record the webcam + the live broadcast into one file";
    after = ["azuracast-live-capture.service" "mediamtx.service"];
    bindsTo = ["azuracast-live-capture.service"];
    wantedBy = ["azuracast-live-capture.service"];
    path = [pkgs.coreutils];
    startLimitIntervalSec = 0;
    serviceConfig = {
      Type = "simple";
      StateDirectory = "azuracast-live-record"; # holds `offset`, below
      # A camera that's unplugged (or a mediamtx still retrying its publish) makes ffmpeg exit
      # immediately; restarting forever is the point - the show keeps recording the moment the
      # camera comes back - but systemd's default start rate limit would give up after 5 tries.
      Restart = "always";
      RestartSec = "10s";
      ExecStart = pkgs.writeShellScript "azuracast-live-record" ''
        # The FLAC mount is the broadcast, so it runs a few seconds behind the mic (darkice's
        # bufferSecs=5 above, plus liquidsoap). -itsoffset delays the *video* by that much to
        # line the two back up. Measure it once by clapping on camera and reading the gap off
        # the recording; write the number of seconds into the file below. No rebuild needed.
        offset="$(cat /var/lib/azuracast-live-record/offset 2>/dev/null)"
        out="/var/lib/media/shows/$(date +%F_%H%M%S).mkv"

        # ?preview= is not needed: /authcheck lets loopback RTSP reads through (see
        # webcam-control.py) - nginx only ever proxies the WebRTC leg, never 8554.
        ${pkgs.ffmpeg}/bin/ffmpeg -nostdin -hide_banner -loglevel warning \
          -itsoffset "''${offset:-0}" -rtsp_transport tcp -i rtsp://127.0.0.1:8554/webcam \
          -i http://127.0.0.1:${toString services.azuracast.port}/listen/radio_marcel/radio.flac \
          -map 0:v -map 1:a -c:v copy -c:a copy -f matroska "$out" || true

        # Every restart above opens a new file; without this a camera-less show leaves one
        # header-only mkv per retry sitting in the library.
        [ "$(stat -c%s "$out")" -gt 1000000 ] || rm -f "$out"
      '';
    };
  };

  security.sudo.extraRules = [
    {
      users = ["azuracast-live-web"];
      commands = [
        {
          command = "/run/current-system/sw/bin/systemctl start azuracast-live-capture";
          options = ["NOPASSWD"];
        }
        {
          command = "/run/current-system/sw/bin/systemctl stop azuracast-live-capture";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];
}
