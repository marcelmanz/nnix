{
  config,
  pkgs,
  services,
  ...
}: let
  # loopback-only; referenced by the "= /listen-time" nginx location in proxy.nix.
  # Kept OUT of the shared `services` attrset on purpose: that attrset feeds the firewall's
  # allowedTCPPorts, and this port must stay loopback-only.
  listenTimePort = 8320;
in {
  imports = [./radio-bot];

  systemd.tmpfiles.rules = [
    "d /var/lib/azuracast 0755 1000 1000 -"
    "d /var/lib/azuracast/stations 0755 1000 1000 -"
    "d /var/lib/azuracast/backups 0755 1000 1000 -"
    "d /var/lib/azuracast/mysql 0755 1000 1000 -"
    "d /var/lib/azuracast/storage 0755 1000 1000 -"
  ];

  virtualisation.oci-containers.containers.azuracast = {
    image = "ghcr.io/azuracast/azuracast:latest";
    environment = {
      APPLICATION_ENV = "production";
      TZ = config.time.timeZone;
      # mariadb is internal to the container (port not published)
      MYSQL_PASSWORD = "azur4c457";
      MYSQL_RANDOM_ROOT_PASSWORD = "yes";
    };
    volumes = [
      "/var/lib/azuracast/stations:/var/azuracast/stations"
      "/var/lib/azuracast/backups:/var/azuracast/backups"
      "/var/lib/azuracast/mysql:/var/lib/mysql"
      "/var/lib/azuracast/storage:/var/azuracast/storage"
      "/var/lib/media/music:/var/azuracast/media/music"
    ];
    ports = ["${toString services.azuracast.port}:80"];
    extraOptions = [
      "--group-add=986"
    ];
  };

  # declarative azuracast settings, applied via the app's own cli so they survive fresh installs and resist ui drift.
  # public_custom_css / public_custom_js are loaded from standalone files (see ./public/public.{css,js}).
  systemd.services.azuracast-settings = {
    description = "Apply declarative AzuraCast settings";
    after = ["podman-azuracast.service"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.podman pkgs.coreutils];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      CSS_FILE=${./public/public.css}
      JS_FILE=${./public/public.js}

      for i in $(seq 1 60); do
        if podman exec azuracast azuracast_cli azuracast:settings:set homepage_redirect_url /public/radio_marcel 2>/dev/null; then
          echo "azuracast-settings: homepage_redirect_url=/public/radio_marcel"

          podman exec azuracast azuracast_cli azuracast:settings:set public_custom_css "$(cat "$CSS_FILE")" 2>/dev/null \
            && echo "azuracast-settings: public_custom_css (from $CSS_FILE)"

          podman exec azuracast azuracast_cli azuracast:settings:set public_custom_js "$(cat "$JS_FILE")" 2>/dev/null \
            && echo "azuracast-settings: public_custom_js (from $JS_FILE)"

          # HLS delivery. The plain mp3 mount is a single endless TCP connection, so any blip on
          # the listener's side kills it outright and nothing server-side can prevent that. HLS
          # ships the same audio as short segments the player fetches ahead and retries
          # individually, so a brief outage costs one segment instead of the whole stream.
          #
          # Both knobs live in the DB with no azuracast_cli setter: enable_hls is a station
          # column, and the actual output needs at least one row in station_hls_streams -
          # enable_hls on its own leaves liquidsoap with nothing to encode and the hls dir empty,
          # which nginx then serves as a 404 (its location does try_files $uri =404).
          #
          # Everything is guarded on current state and the radio is restarted at most once,
          # because azuracast:radio:restart disconnects every listener - unguarded, each
          # nixos-rebuild would drop the whole audience.
          mysql() { podman exec azuracast mariadb -N -B -u azuracast -p${config.virtualisation.oci-containers.containers.azuracast.environment.MYSQL_PASSWORD} azuracast -e "$1" 2>/dev/null; }

          SID=$(mysql "SELECT id FROM station WHERE short_name='radio_marcel';")
          RADIO_CHANGED=0

          # avoid_duplicates makes the queue builder skip any track whose artist played
          # recently. With an album-shaped library that means it selects artist-uniformly
          # instead of track-uniformly: a 1-track artist got 18 plays in 3 days while each
          # track of a 13-track album got 2.6. It also wipes the shuffle cycle whenever
          # nothing passes the filter ("Duplicate prevention yielded no playable song;
          # resetting song queue"), so the library never finishes a full pass. Off = plain
          # shuffle, every track once per ~14h cycle.
          if [ "$(mysql "SELECT avoid_duplicates FROM station_playlists WHERE station_id=$SID AND name='default';")" = "1" ]; then
            mysql "UPDATE station_playlists SET avoid_duplicates=0 WHERE station_id=$SID AND name='default';" \
              && echo "azuracast-settings: avoid_duplicates=0"
          fi

          if [ "$(mysql "SELECT enable_hls FROM station WHERE id=$SID;")" = "0" ]; then
            if mysql "UPDATE station SET enable_hls=1 WHERE id=$SID;"; then
              RADIO_CHANGED=1
              echo "azuracast-settings: enable_hls=1"
            fi
          fi

          if [ "$(mysql "SELECT COUNT(*) FROM station_hls_streams WHERE station_id=$SID;")" = "0" ]; then
            if mysql "INSERT INTO station_hls_streams (station_id, name, format, bitrate, listeners) VALUES ($SID, 'aac_192', 'aac', 192, 0);"; then
              RADIO_CHANGED=1
              echo "azuracast-settings: added hls stream aac_192"
            fi
          fi

          # FLAC mount for the /lossless-stream alias in proxy.nix. Not the default mount:
          # /stream (radio.mp3) keeps serving web/mobile listeners, FLAC is opt-in by URL.
          # autodj_bitrate is inert for FLAC (liquidsoap %flac is compression-based) - 0 keeps
          # the API honest instead of advertising a fake kbps. All NOT NULL columns are set
          # explicitly because DB-side defaults on station_mounts are not guaranteed.
          if [ "$(mysql "SELECT COUNT(*) FROM station_mounts WHERE station_id=$SID AND name='/radio.flac';")" = "0" ]; then
            if mysql "INSERT INTO station_mounts (station_id, name, display_name, is_visible_on_public_pages, is_default, is_public, max_listener_duration, enable_autodj, autodj_format, autodj_bitrate, listeners_unique, listeners_total) VALUES ($SID, '/radio.flac', 'FLAC', 1, 0, 0, 0, 1, 'flac', 0, 0, 0);"; then
              RADIO_CHANGED=1
              echo "azuracast-settings: added flac mount /radio.flac"
            fi
          fi

          # Selector labels for the player's built-in stream dropdown: its item titles are the
          # mounts' display_name, so they name the format and its bitrate. FLAC carries no
          # number - liquidsoap's %flac is compression-based, so its rate floats with the
          # material (~1 Mbps measured); a fixed kbps there would be a lie. Cosmetic, DB-only
          # values - no radio restart needed. The player itself prepends a fixed "HLS" entry
          # whenever HLS is enabled; that one is not renamable from the DB.
          if [ "$(mysql "SELECT display_name FROM station_mounts WHERE station_id=$SID AND name='/radio.mp3';")" != "MP3 192k" ]; then
            mysql "UPDATE station_mounts SET display_name='MP3 192k' WHERE station_id=$SID AND name='/radio.mp3';" \
              && echo "azuracast-settings: mp3 mount labelled 'MP3 192k'"
          fi
          if [ "$(mysql "SELECT display_name FROM station_mounts WHERE station_id=$SID AND name='/radio.flac';")" != "FLAC" ]; then
            mysql "UPDATE station_mounts SET display_name='FLAC' WHERE station_id=$SID AND name='/radio.flac';" \
              && echo "azuracast-settings: flac mount labelled 'FLAC'"
          fi

          # Repair rows written with a type the current PlaylistTypes enum no longer has (an
          # older revision inserted 'scheduled'). Hydrating one such row throws, which breaks
          # the whole playlist listing - scheduling comes from station_schedules, not the type.
          VALID_TYPES="'default','once_per_x_songs','once_per_x_minutes','once_per_hour'"
          if [ "$(mysql "SELECT COUNT(*) FROM station_playlists WHERE station_id=$SID AND type NOT IN ($VALID_TYPES);")" != "0" ]; then
            mysql "UPDATE station_playlists SET type='default' WHERE station_id=$SID AND type NOT IN ($VALID_TYPES);" \
              && echo "azuracast-settings: reset invalid playlist type(s) to 'default'"
          fi

          # News bulletin playlist. radio-bot generates a bulletin at 07:30 and 16:30 and
          # uploads it to the news/ folder; the folder row below makes AzuraCast attach each
          # upload to this playlist on arrival (FlowUploadAction does that for any directory
          # with a playlist binding), so no per-run playlist call is needed.
          #
          # station_schedules + loop_once: the bulletin plays once at the top of each window rather
          # than looping for its whole length. The windows sit ~30 min after each generation
          # run so the greeting the script writes ("good morning" / "good afternoon") matches
          # when it actually airs. radio-bot prunes older bulletins after each upload, so the
          # playlist only ever holds the current one.
          NEWS_PID=$(mysql "SELECT id FROM station_playlists WHERE station_id=$SID AND name='news';")
          if [ -z "$NEWS_PID" ]; then
            mysql "INSERT INTO station_playlists (station_id, name, type, is_enabled, play_per_songs, play_per_minutes, weight, source, include_in_requests, playback_order, is_jingle, play_per_hour_minute, remote_timeout, include_in_on_demand, avoid_duplicates) VALUES ($SID, 'news', 'default', 1, 0, 0, 20, 'songs', 0, 'sequential', 0, 0, 0, 0, 0);"
            NEWS_PID=$(mysql "SELECT id FROM station_playlists WHERE station_id=$SID AND name='news';")
            echo "azuracast-settings: created 'news' playlist (id=$NEWS_PID)"
          fi

          if [ "$(mysql "SELECT weight FROM station_playlists WHERE id=$NEWS_PID;")" != "20" ]; then
            mysql "UPDATE station_playlists SET weight=20 WHERE id=$NEWS_PID;" \
              && echo "azuracast-settings: news playlist weight=20"
          fi

          if [ -n "$NEWS_PID" ]; then
            ensure_schedule() {
              if [ "$(mysql "SELECT COUNT(*) FROM station_schedules WHERE playlist_id=$NEWS_PID AND start_time=$1;")" = "0" ]; then
                mysql "INSERT INTO station_schedules (playlist_id, start_time, end_time, loop_once, prevent_requests) VALUES ($NEWS_PID, $1, $2, 1, 0);" \
                  && echo "azuracast-settings: news airs $1-$2"
              fi
            }
            ensure_schedule 800 815
            ensure_schedule 1700 1715

            if [ "$(mysql "SELECT COUNT(*) FROM station_playlist_folders WHERE station_id=$SID AND playlist_id=$NEWS_PID AND path='news';")" = "0" ]; then
              mysql "INSERT INTO station_playlist_folders (station_id, playlist_id, path) VALUES ($SID, $NEWS_PID, 'news');" \
                && echo "azuracast-settings: bound news/ folder to the news playlist"
            fi
          fi

          if [ "$RADIO_CHANGED" = "1" ]; then
            podman exec azuracast azuracast_cli azuracast:radio:restart radio_marcel 2>/dev/null \
              && echo "azuracast-settings: radio restarted for hls"
          else
            echo "azuracast-settings: hls already configured, leaving radio alone"
          fi

          exit 0
        fi
        sleep 5
      done
      echo "azuracast-settings: gave up; last error:" >&2
      podman exec azuracast azuracast_cli azuracast:settings:set homepage_redirect_url /public/radio_marcel >&2
      exit 1
    '';
  };

  # Auto-add every file under /var/lib/media/music to the default rotation.
  # AzuraCast imports new files into station_media within ~1 min but never adds
  # them to a playlist, so they sit imported-but-unplayed. The native 5-min
  # CheckFolderPlaylistsTask links folder-matched media into a playlist and
  # prunes stale rows - but it matches `sm.path LIKE path.'/%'` and
  # station_media.path is relative with no leading slash, so NO folder path
  # matches the library root; only one row per top-level subfolder works. This
  # just ensures those rows exist idempotently (no unique key on
  # station_playlist_folders, hence NOT EXISTS); the native task does the actual
  # linking and dedupes via addMediaToPlaylist for shuffle playlists, so the
  # 138 manually-linked tracks get adopted, not doubled. New artists dropped in
  # by bandcampsync join rotation within ~10 min - no per-sync glue needed in
  # bandcampsync.nix.
  systemd.services.azuracast-autoplaylist = {
    description = "Link default AzuraCast playlist to every top-level media folder";
    after = ["podman-azuracast.service"];
    path = [pkgs.podman pkgs.coreutils];
    serviceConfig.Type = "oneshot";
    script = ''
      mysql() { podman exec azuracast mariadb -N -B -u azuracast -p${config.virtualisation.oci-containers.containers.azuracast.environment.MYSQL_PASSWORD} azuracast -e "$1" 2>/dev/null; }

      # `|| true` on the two probes only: nixos runs this script under `sh -e`, so a failed
      # query (container up but mariadb not listening yet) would abort with status 1 before
      # reaching the guard below, reporting a routine startup race as a failed unit. The
      # inserts further down keep their default behaviour - those failures are real.
      SID=$(mysql "SELECT id FROM station WHERE short_name='radio_marcel';") || true
      PID=$(mysql "SELECT id FROM station_playlists WHERE station_id=$SID AND name='default' AND source='songs' LIMIT 1;") || true
      [ -n "$SID" ] && [ -n "$PID" ] || { echo "azuracast-autoplaylist: station/playlist not ready"; exit 0; }

      # quote-doubling (MariaDB single-quoted string escape) for apostrophes in folder names
      q="'"
      # 'news' is excluded: radio-bot uploads bulletins there and they get their own
      # scheduled playlist, so they must not join the music rotation.
      find /var/lib/media/music -maxdepth 1 -mindepth 1 -type d ! -name '.*' ! -name news -printf '%f\n' 2>/dev/null \
        | while IFS= read -r dir; do
            esc=$(printf '%s' "$dir" | sed "s/$q/$q$q/g")
            mysql "INSERT INTO station_playlist_folders (station_id, playlist_id, path) SELECT $SID, $PID, '$esc' FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM station_playlist_folders WHERE station_id=$SID AND playlist_id=$PID AND path='$esc');"
          done
      echo "azuracast-autoplaylist: ensured folder rows for station=$SID playlist=$PID"
    '';
  };

  systemd.timers.azuracast-autoplaylist = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
      AccuracySec = "30s";
      RandomizedDelaySec = "1m";
    };
  };

  # Per-IP listen-time endpoint for the public radio page. The public AzuraCast API only exposes
  # aggregate listener counts; the per-IP numbers live in the DB `listener` table, so this small
  # service reads them via podman exec (same pattern as azuracast-settings/autoplaylist) and
  # serves GET /listen-time on 127.0.0.1. Nginx fronts it as same-origin /listen-time
  # (proxy.nix) with X-Real-IP/X-Forwarded-For = the client, so each visitor only ever gets back
  # their own aggregate.
  systemd.services.azuracast-listen-time = {
    description = "Per-IP listen-time endpoint for the radio public page";
    after = ["network.target" "podman-azuracast.service"];
    wants = ["podman-azuracast.service"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.podman];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.python3}/bin/python3 ${./listen-time.py} ${toString listenTimePort}";
      Environment = [
        "MYSQL_PASSWORD=${config.virtualisation.oci-containers.containers.azuracast.environment.MYSQL_PASSWORD}"
      ];
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
