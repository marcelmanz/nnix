{
  pkgs,
  config,
  services,
  ...
}: let
  htmlDir = "/var/lib/bandcampsync-status";
  reportPy = ./bandcampsync_report.py;
  controlPort = 8292;

  # bpm + key tags after every sync; idempotent (skips already-tagged files),
  # so `dj-enrich` also works as a backfill on the existing library.
  djEnrich = pkgs.writeShellApplication {
    name = "dj-enrich";
    runtimeInputs = [
      (pkgs.python313.withPackages (ps: [ps.mutagen ps.aubio-ledfx]))
      pkgs.keyfinder-cli
      pkgs.ffmpeg-headless
      pkgs.rsgain
      pkgs.coreutils
    ];
    text = ''
      if [ "$#" -eq 0 ]; then set -- /var/lib/media/dj /var/lib/media/music; fi
      python3 ${./dj-enrich.py} "$@" || true  # tagger crash must not block rsgain/navidrome rescan
      rsgain easy "$@" || true  # replaygain; tolerate unsupported files
    '';
  };

  beetsMusicDir = "/var/lib/beets-music";
  beetsMusicConfig = pkgs.writeText "beets-music.yaml" ''
    directory: /var/lib/media/music
    library: ${beetsMusicDir}/library.db
    ignore: [".*", "*~", "news"]

    plugins: bandcamp zero

    import:
      copy: no
      move: no
      write: yes
      quiet: yes
      quiet_fallback: skip
      duplicate_action: skip
      incremental: yes
      incremental_skip_later: yes
      resume: no
      log: ${beetsMusicDir}/import.log

    match:
      strong_rec_thresh: 0.5
      max_rec:
        missing_tracks: strong
        unmatched_tracks: strong

    bandcamp:
      exclude_extra_fields: [comments]
      genre:
        capitalize: yes

    zero:
      fields: mb_albumid mb_trackid mb_artistid mb_artistids mb_albumartistid mb_albumartistids mb_releasetrackid mb_releasegroupid
  '';
  musicBeet = pkgs.writeShellApplication {
    name = "music-beet";
    runtimeInputs = [
      (pkgs.python3Packages.beets.override {
        pluginOverrides.beetcamp = {
          enable = true;
          propagatedBuildInputs = [
            (pkgs.python3Packages.beetcamp.overridePythonAttrs (old: {
              postPatch =
                (old.postPatch or "")
                + ''
                  substituteInPlace beetcamp/http.py --replace-fail \
                    'USER_AGENT = f"beets/{beets.__version__} +https://beets.io/"' \
                    'USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"'
                '';
            }))
          ];
        };
      })
    ];
    text = ''
      export BEETSDIR=${beetsMusicDir}
      exec beet -c ${beetsMusicConfig} "$@"
    '';
  };
  musicBeetImport = pkgs.writeShellApplication {
    name = "music-beet-import";
    runtimeInputs = [musicBeet pkgs.jq pkgs.findutils pkgs.coreutils];
    text = ''
      find /var/lib/media/music -name bandcamp_item_id.txt -print0 | while IFS= read -r -d "" item_id_file; do
        url=$(jq -r --arg id "$(tr -d '[:space:]' < "$item_id_file")" '.[$id] // empty' ${htmlDir}/urls.json)
        if [ -z "$url" ]; then
          echo "no purchase url: $(dirname "$item_id_file")" >&2
          continue
        fi
        music-beet import -S "$url" "$(dirname "$item_id_file")" < /dev/null || true
      done
      music-beet modify -a -y 'genres::^$' 'style::.' "genres=\$style"
    '';
  };
  djGenres = pkgs.writeShellApplication {
    name = "dj-genres";
    runtimeInputs = [(pkgs.python313.withPackages (ps: [ps.mutagen]))];
    text = ''
      python3 ${./dj-genres.py} "$@"
    '';
  };
in {
  systemd.tmpfiles.rules = [
    "d ${beetsMusicDir} 0750 root root -"
  ];

  # bandcamp cookies arrive via syncthing from laptop (see syncthing.nix)

  systemd.services.bandcampsync = {
    description = "Sync Bandcamp collection to music (flac) and dj (aiff)";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    path = [pkgs.bash pkgs.coreutils pkgs.curl pkgs.python313Packages.pipx];
    onFailure = ["bandcampsync-report.service"];
    unitConfig.OnSuccess = "bandcampsync-report.service";
    script = ''
      set -e
      # filter to bandcamp-only cookies (full-profile exports break the tool)
      grep bandcamp /var/lib/syncthing/bandcamp-cookies/cookies.txt > /run/bandcamp_cookies_filtered.txt
      chmod 400 /run/bandcamp_cookies_filtered.txt
      # fetch real bandcamp album URLs (id -> item_url) from collection metadata
      pipx run --spec bandcampsync python3 ${reportPy} fetch-urls
      # bandcampsync's collection checkpoint always advances to the newest item, and
      # the checkpoint item itself is excluded from processing. So an unreleased
      # preorder that gets skipped is never revisited once it releases. Clear the
      # state each run to force a full re-scan; the bandcamp_item_id.txt index already
      # prevents re-downloading synced albums, so the re-scan is cheap.
      rm -f /var/lib/media/music/.bandcampsync-state.json /var/lib/media/dj/.bandcampsync-state.json
      pipx run bandcampsync -c /run/bandcamp_cookies_filtered.txt -d /var/lib/media/music -f flac --skip-hidden
      pipx run bandcampsync -c /run/bandcamp_cookies_filtered.txt -d /var/lib/media/dj -f aiff-lossless --skip-hidden
      rm /run/bandcamp_cookies_filtered.txt
      # bandcampsync's own mkdir/writes don't inherit the media group or give
      # group/world access; syncthing (group media) needs read on files and
      # write on directories (to rename-normalize Unicode filenames), and tagr
      # (also group media) rewrites tags in place, so files are group-writable
      # too. Normalize both trees after every run.
      for tree in /var/lib/media/dj /var/lib/media/music; do
        chgrp -R media "$tree"
        find "$tree" -type d -exec chmod 2775 {} +
        find "$tree" -type f -exec chmod 0664 {} +
      done
      ${musicBeetImport}/bin/music-beet-import || true
      ${djGenres}/bin/dj-genres || true
      # tag new files with bpm + key + replaygain (skips already-tagged ones)
      ${djEnrich}/bin/dj-enrich
      # trigger a navidrome full scan so new tracks show up right away
      curl -fsS "http://127.0.0.1:${toString services.navidrome.port}/rest/startScan.view?u=$(cat ${config.sops.secrets.web_user.path})&t=$(cat ${config.sops.secrets.navidrome_token.path})&s=$(cat ${config.sops.secrets.navidrome_salt.path})&v=1.16.1&c=bandcampsync&f=json&fullScan=true" > /dev/null
    '';
  };

  # cheap poll (1-2 bandcamp requests) so a new purchase gets synced within
  # minutes instead of waiting for the next 8h-apart full-sync slot
  systemd.services.bandcampsync-check = {
    description = "Poll bandcamp collection for a new purchase, trigger sync on change";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    path = [pkgs.bash pkgs.coreutils pkgs.systemd pkgs.python313Packages.pipx];
    script = ''
      set -e
      grep bandcamp /var/lib/syncthing/bandcamp-cookies/cookies.txt > /run/bandcamp_cookies_filtered.txt
      chmod 400 /run/bandcamp_cookies_filtered.txt
      set +e
      pipx run --spec bandcampsync python3 ${reportPy} check
      rc=$?
      set -e
      rm -f /run/bandcamp_cookies_filtered.txt
      if [ "$rc" -eq 2 ]; then
        systemctl start bandcampsync.service
      elif [ "$rc" -ne 0 ]; then
        exit "$rc"
      fi
    '';
  };

  systemd.timers.bandcampsync-check = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitActiveSec = "15m";
      RandomizedDelaySec = "1m";
    };
  };

  # "Sync now" button on the status page (see bandcampsync-control.py). Unprivileged
  # user + a single NOPASSWD sudo rule, same pattern as webcam-control.py.
  users.users.bandcampsync-control = {
    isSystemUser = true;
    group = "bandcampsync-control";
  };
  users.groups.bandcampsync-control = {};

  security.sudo.extraRules = [
    {
      users = ["bandcampsync-control"];
      commands = [
        {
          command = "/run/current-system/sw/bin/systemctl start --no-block bandcampsync.service";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];

  systemd.services.bandcampsync-control = {
    description = "Manual bandcamp sync trigger (bcsync.marcel.cool sync button)";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "simple";
      User = "bandcampsync-control";
      ExecStart = "${pkgs.python3}/bin/python3 ${./bandcampsync-control.py} ${toString controlPort}";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  systemd.services.bandcampsync-report = {
    description = "Generate bandcampsync status html";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Environment = "PYTHONTZPATH=${pkgs.tzdata}/share/zoneinfo";
    };
    path = [pkgs.bash pkgs.python313 pkgs.systemd];
    script = "${pkgs.python313}/bin/python3 ${reportPy} generate";
  };

  # static status page at https://bcsync.marcel.cool, gated to group:admins (see
  # authelia.nix). links.json is the one exception: the azuracast public page
  # (different origin, no login) fetches it to turn now-playing artist names into
  # bandcamp links, so it stays public with its own CORS header.
  services.nginx.virtualHosts."bcsync.marcel.cool" = {
    forceSSL = true;
    useACMEHost = "marcel.cool";
    root = htmlDir;
    locations."= /links.json" = {
      extraConfig = ''
        autoindex off;
        add_header Access-Control-Allow-Origin * always;
      '';
    };
    locations."= /sync" = {
      proxyPass = "http://127.0.0.1:${toString controlPort}/sync";
      extraConfig = ''
        limit_except POST { deny all; }
        auth_request /internal/authelia/authz;
        error_page 401 = @authelia_login;
      '';
    };
    locations."/" = {
      extraConfig = ''
        autoindex off;
        auth_request /internal/authelia/authz;
        error_page 401 = @authelia_login;
      '';
    };
    extraConfig = ''
      location /internal/authelia/authz {
        internal;
        proxy_pass http://127.0.0.1:${toString services.auth.port}/api/verify;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
        proxy_set_header X-Forwarded-Method $request_method;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-URI $request_uri;
        proxy_set_header X-Forwarded-For $remote_addr;
      }
      location @authelia_login {
        return 302 https://auth.marcel.cool/?rd=$scheme://$http_host$request_uri&rm=$request_method;
      }
    '';
  };

  environment.systemPackages = [djEnrich musicBeet musicBeetImport djGenres];

  systemd.timers.bandcampsync = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = ["08:00" "16:00" "00:00"];
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };
}
