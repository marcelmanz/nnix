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
  # snd-aloop gives 8 independent cables, and ALSA allows exactly one capture client per
  # cable - a second reader gets EBUSY. So every consumer of the mix gets its own:
  #   cable 0  darkice (azuracast-live-capture)
  #   cable 1  azuracast-live-record
  #   cable 2  the level meter on live.marcel.cool (polls continuously)
  #   cable 3  the sync test and mic test (brief, user-initiated)
  #   cable 4  azuracast-live-monitor (the WebRTC desk monitor, see below)
  # Verified that a cable with no reader doesn't stall its writer, so the unused ones are free.
  boot.kernelModules = ["snd-aloop"];

  # Mixes the Scarlett 2i2 (card USB) and the Amazon USB mic (card Mic) and plays the result into
  # the loopback card's device 0 - azuracast-live-capture below reads it back from device 1.
  # aresample=async=1 on each leg: the two USB interfaces free-run on independent clocks, so
  # without it they'd slowly drift apart; this lets ffmpeg stretch/compress each leg a little to
  # stay in sync instead of glitching.
  # Always on, not just during a show: the recorder, the sync test and the level meter all
  # read cable 1 below, and they need to work before you go on air. An idle mixer is harmless
  # on its own - it's darkice (azuracast-live-capture) that would put dead air over the
  # auto-DJ, and that still only starts when you press the button.
  systemd.services.azuracast-live-mix = {
    description = "Mix Scarlett 2i2 + USB mic into the loopback device darkice reads from";
    after = ["sound.target"];
    wantedBy = ["multi-user.target"];
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
          | ${pkgs.coreutils}/bin/tee --output-error=warn-nopipe \
              >(${pkgs.alsa-utils}/bin/aplay -D plughw:CARD=Loopback,DEV=0,1 -f S16_LE -r 44100 -c 2 \
                  --buffer-time=200000 --period-time=50000 >/dev/null 2>&1) \
              >(${pkgs.alsa-utils}/bin/aplay -D plughw:CARD=Loopback,DEV=0,2 -f S16_LE -r 44100 -c 2 \
                  --buffer-time=200000 --period-time=50000 >/dev/null 2>&1) \
              >(${pkgs.alsa-utils}/bin/aplay -D plughw:CARD=Loopback,DEV=0,3 -f S16_LE -r 44100 -c 2 \
                  --buffer-time=200000 --period-time=50000 >/dev/null 2>&1) \
              >(${pkgs.alsa-utils}/bin/aplay -D plughw:CARD=Loopback,DEV=0,4 -f S16_LE -r 44100 -c 2 \
                  --buffer-time=200000 --period-time=50000 >/dev/null 2>&1) \
          | ${pkgs.alsa-utils}/bin/aplay -D plughw:CARD=Loopback,DEV=0,0 -f S16_LE -r 44100 -c 2 \
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
      ExecStart = "${pkgs.python3}/bin/python3 ${./live-toggle.py} ${toString services.livedj.port} ${pkgs.alsa-utils}/bin/amixer ${pkgs.ffmpeg}/bin/ffmpeg ${pkgs.ffmpeg}/bin/ffprobe ${toString services.streamcam.port}";
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
  # Owned by the web user, not the recorder: azuracast-live-web writes `offset` from the
  # live.marcel.cool deck, and the recorder (root) only ever reads it.
  # The file as well as the directory: the recorder used to own this path via StateDirectory
  # and left a root-owned `offset` behind, which the page then couldn't overwrite. `z` fixes
  # an existing one, `f` creates it when absent.
  systemd.tmpfiles.rules = [
    "d /var/lib/azuracast-live-record 0755 azuracast-live-web azuracast-live-web -"
    "f /var/lib/azuracast-live-record/offset 0644 azuracast-live-web azuracast-live-web -"
    "z /var/lib/azuracast-live-record/offset 0644 azuracast-live-web azuracast-live-web -"
  ];

  systemd.services.azuracast-live-record = {
    description = "Record the webcam + the live broadcast into one file";
    after = ["azuracast-live-capture.service" "mediamtx.service"];
    bindsTo = ["azuracast-live-capture.service"];
    wantedBy = ["azuracast-live-capture.service"];
    path = [pkgs.coreutils];
    startLimitIntervalSec = 0;
    serviceConfig = {
      Type = "simple";
      # A camera that's unplugged (or a mediamtx still retrying its publish) makes ffmpeg exit
      # immediately; restarting forever is the point - the show keeps recording the moment the
      # camera comes back - but systemd's default start rate limit would give up after 5 tries.
      Restart = "always";
      RestartSec = "10s";
      ExecStart = pkgs.writeShellScript "azuracast-live-record" ''
        # Audio comes off the desk (loopback cable 1 = the Scarlett + mic mix), never the
        # broadcast mount: the mount carries the auto-DJ whenever you're not live, and it
        # trails the room by ~6s (liquidsoap's harbor buffer=5.00 plus icecast's burst), which
        # is latency there's no reason to record and then undo. Straight off the desk the two
        # legs are within a few hundred ms, so `offset` is a small trim, not a 6s correction.
        offset="$(cat /var/lib/azuracast-live-record/offset 2>/dev/null)"

        # exec, so ffmpeg *is* the main process. Left as a child of this shell it gets the
        # control-group SIGTERM while already shutting down, reads the second signal as
        # "immediate exit", and abandons the Matroska trailer - the file then has no duration
        # and players call it truncated. The small-file sweep this shell used to do afterwards
        # moved to ExecStopPost for the same reason.

        # ?preview= is not needed: /authcheck lets loopback RTSP reads through (see
        # webcam-control.py) - nginx only ever proxies the WebRTC leg, never 8554.
        exec ${pkgs.ffmpeg}/bin/ffmpeg -nostdin -hide_banner -loglevel warning \
          -itsoffset "''${offset:-0}" -rtsp_transport tcp -i rtsp://127.0.0.1:8554/webcam \
          -f alsa -ar 44100 -ac 2 -i plughw:CARD=Loopback,DEV=1,1 \
          -map 0:v -map 1:a -c:v copy -c:a flac \
          -f matroska "/var/lib/media/live-recordings/$(date +%F_%H%M%S).mkv"
      '';
      # Each restart opens a new file; without this sweep a camera-less show leaves one
      # header-only mkv per retry in the library. Bounded to this directory, and a real
      # recording is never under 1M (~2.7GB/h).
      ExecStopPost = "${pkgs.findutils}/bin/find /var/lib/media/live-recordings -maxdepth 1 -name '*.mkv' -size -1M -delete";
      TimeoutStopSec = "30s"; # room for ffmpeg to write the trailer after SIGTERM
    };
  };

  # The desk monitor: the same mix, but out over WebRTC instead of down the radio chain.
  # The broadcast leg trails the room by ~16s (darkice bufferSecs=5, liquidsoap's harbor
  # buffer=5.00, icecast's burst, then whatever the listening phone buffers on top), which
  # is useless for following the desk from another room. This pushes cable 4 into mediamtx
  # as Opus and lets WebRTC's jitter buffer be the only thing in the way - under a second on
  # the LAN. Publishing to loopback RTSP, which /authcheck already allows (webcam-control.py).
  # Always on for the same reason the mixer is: nothing here reaches the broadcast, and a
  # monitor you have to go and start is a monitor you find out is off mid-show.
  systemd.services.azuracast-live-monitor = {
    description = "Publish the live mix to mediamtx for sub-second LAN monitoring";
    after = ["sound.target" "azuracast-live-mix.service" "mediamtx.service"];
    bindsTo = ["azuracast-live-mix.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      RestartSec = "5s";
      # libopus only encodes at 8/12/16/24/48k, so the output rate is set explicitly rather
      # than left to ffmpeg's implicit resample off the loopback's 44100.
      # exec, so ffmpeg is the main process and gets the stop signal directly.
      ExecStart = pkgs.writeShellScript "azuracast-live-monitor" ''
        exec ${pkgs.ffmpeg}/bin/ffmpeg -nostdin -hide_banner -loglevel warning \
          -fflags nobuffer -flags low_delay \
          -f alsa -ar 44100 -ac 2 -i plughw:CARD=Loopback,DEV=1,4 \
          -c:a libopus -ar 48000 -b:a 128k -application lowdelay -frame_duration 20 \
          -rtsp_transport tcp -f rtsp rtsp://127.0.0.1:8554/livemix
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
