{
  config,
  pkgs,
  services,
  ...
}: {
  imports = [./radio-bot ./live.nix ./webcam.nix];

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
    # 8005 = liquidsoap's DJ/streamer harbor (station backend_config.dj_port), loopback-only:
    # only the local azuracast-live-capture service (live.nix) connects to it.
    ports = ["${toString services.azuracast.port}:80" "127.0.0.1:8005:8005"];
    extraOptions = [
      "--group-add=986"
    ];
  };

  # declarative azuracast settings, applied via the app's own cli so they survive fresh installs and resist ui drift.
  systemd.services.azuracast-settings = {
    description = "Apply declarative AzuraCast settings";
    after = ["podman-azuracast.service"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.podman pkgs.coreutils pkgs.gnused];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mysql() { podman exec azuracast mariadb -N -B -u azuracast -p${config.virtualisation.oci-containers.containers.azuracast.environment.MYSQL_PASSWORD} azuracast -e "$1" 2>/dev/null; }

      for i in $(seq 1 60); do
        SID=$(mysql "SELECT id FROM station WHERE short_name='radio_marcel';") || true
        if [ -n "$SID" ]; then
          # Everything is guarded on current state and the radio is restarted at most once,
          # because azuracast:radio:restart disconnects every listener - unguarded, each
          # nixos-rebuild would drop the whole audience.
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

          # Icecast hands every new listener burst-size bytes the moment it connects, and that
          # is all the buffer the player ever gets: after it the stream arrives at realtime.
          # 65535 (~2.7s at 192kbps, AzuraCast's default) is kept explicit over a lower value:
          # 16384 (~0.7s) cut ~2s of lag but made every start stutter. The lag no longer matters
          # since resona's live mode plays the synced video stream, not this mount.
          # custom_config is merged recursively over the generated config (Radio/Frontend/Icecast.php).
          BURST_CFG='{"limits":{"burst-size":65535}}'
          if [ "$(mysql "SELECT JSON_UNQUOTE(JSON_EXTRACT(frontend_config, '\$.custom_config')) FROM station WHERE id=$SID;")" != "$BURST_CFG" ]; then
            if mysql "UPDATE station SET frontend_config=JSON_SET(frontend_config, '\$.custom_config', '$BURST_CFG') WHERE id=$SID;"; then
              RADIO_CHANGED=1
              echo "azuracast-settings: icecast burst-size=65535"
            fi
          fi

          if [ "$RADIO_CHANGED" = "1" ]; then
            podman exec azuracast azuracast_cli azuracast:radio:restart radio_marcel 2>/dev/null \
              && echo "azuracast-settings: radio restarted"
          else
            echo "azuracast-settings: station already configured, leaving radio alone"
          fi

          exit 0
        fi
        sleep 5
      done
      echo "azuracast-settings: gave up waiting for the radio_marcel station" >&2
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

  # Public page at radio.marcel.cool: radio, live video+desk audio, chat (codeberg.org/marcelmanz/resona).
  services.resona = {
    enable = true;
    domain = "radio.marcel.cool";
  };
}
