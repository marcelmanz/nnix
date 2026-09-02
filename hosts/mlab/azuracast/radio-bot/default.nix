{
  config,
  pkgs,
  services,
  ...
}: let
  # Bulletin archive: the mp3s and the index.html the bot writes each run, served as-is by the
  # vhost below. Same shape as bandcampsync's status page.
  htmlDir = "/var/lib/radio-news";

  # Kokoro-82M rather than piper: piper's top tier ("high") still has an audible metallic
  # vocoder edge, and kokoro renders at 24kHz instead of 22.05kHz. Weights are fetched at build
  # time so the unit never touches huggingface at runtime.
  kokoroBase = "https://huggingface.co/hexgrad/Kokoro-82M/resolve/main";
  kokoroConfig = pkgs.fetchurl {
    url = "${kokoroBase}/config.json";
    hash = "sha256-WrsB4kA7ByvwPQT94WBEPiCdeg2tSaQjvhUZa5tDwX8=";
  };
  kokoroModel = pkgs.fetchurl {
    url = "${kokoroBase}/kokoro-v1_0.pth";
    hash = "sha256-SW26EY0aWPXz2y78iNvcIW4Eg/yJ/m5H7h8sU/GK0eQ=";
  };
  kokoroVoice = pkgs.fetchurl {
    url = "${kokoroBase}/voices/am_michael.pt";
    hash = "sha256-mkQ7eaSyJImlsKt8ZRoLzRowvvZ1woMz8Glxq71HvTc=";
  };

  # spacy-models.en_core_web_sm is misaki's English G2P dependency; without it kokoro dies at
  # import with "Can't find model 'en_core_web_sm'".
  python = pkgs.python3.withPackages (p: [
    p.requests
    p.kokoro
    p.misaki
    p.soundfile
    p.numpy
    p.spacy-models.en_core_web_sm
  ]);
in {
  sops.secrets."azuracast_api_key" = {
    owner = "dev";
    mode = "0400";
  };

  sops.templates."radio-bot.env" = {
    content = ''
      MINIFLUX_API_KEY=${config.sops.placeholder.miniflux_api}
      SYNTHETIC_API_KEY=${config.sops.placeholder.synthetic_api_key}
      AZURACAST_API_KEY=${config.sops.placeholder.azuracast_api_key}
    '';
    owner = "dev";
    mode = "0400";
  };

  systemd.services.azuracast-radio-bot = {
    description = "Generate and upload AI radio news bulletin";
    wants = ["network-online.target"];
    after = ["network-online.target" "miniflux.service" "podman-azuracast.service"];
    path = [pkgs.ffmpeg];

    # `environment`, not serviceConfig.Environment: the latter renders one unquoted
    # `Environment=` line per entry, and systemd splits those on whitespace - BED_FILE arrived as
    # "/var/lib/media/music/Paddy" and every bulletin silently went out without music. This
    # option quotes each value, so paths with spaces survive.
    environment = {
      MINIFLUX_URL = "http://127.0.0.1:${toString services.miniflux.port}";
      # not the loopback port: AzuraCast 307-redirects every API call to its own https
      # base url, and a redirected multipart POST cannot replay its already-read body.
      AZURACAST_URL = services.azuracast.href;
      KOKORO_CONFIG = "${kokoroConfig}";
      KOKORO_MODEL = "${kokoroModel}";
      KOKORO_VOICE = "${kokoroVoice}";
      MORNING_DOC = "${./morning.md}";
      AFTERNOON_DOC = "${./afternoon.md}";
      # Cover art is rendered per run by the bot; the bold ttf is its only input beyond the date.
      NEWS_ART_FONT = "${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans-Bold.ttf";
      # Deliberately a library path, not a store path: a 50MB flac does not belong in the
      # repo, and a missing bed downgrades to a dry read instead of failing the bulletin.
      BED_FILE = "/var/lib/media/music/Paddy Thorne/Lost Cause (Part Two)/Paddy Thorne - Lost Cause (Part Two) - 08 Rendered.flac";
      ARCHIVE_DIR = htmlDir;
      TZ = config.time.timeZone;
      PYTHONTZPATH = "${pkgs.tzdata}/share/zoneinfo";
    };

    serviceConfig = {
      Type = "oneshot";
      User = "dev";
      EnvironmentFile = config.sops.templates."radio-bot.env".path;
      ExecStart = "${python}/bin/python3 ${./radio-bot.py}";
      # 0755, not the 0700 default: nginx has to read the archive back out.
      StateDirectory = "radio-news";
      StateDirectoryMode = "0755";
    };
  };

  # static bulletin archive at https://bulletins.marcel.cool (linked from the radio-program
  # popover on the public player, see public.js)
  services.nginx.virtualHosts."bulletins.marcel.cool" = {
    forceSSL = true;
    useACMEHost = "marcel.cool";
    root = htmlDir;
    extraConfig = "autoindex off;";
  };

  systemd.timers.azuracast-radio-bot = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = ["07:30" "16:30"];
      Persistent = true;
    };
  };
}
