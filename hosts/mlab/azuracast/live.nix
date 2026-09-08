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
      Type = "simple";
      # ffmpeg's own alsa output negotiates a 128-frame (~3ms) period against Loopback's
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
