{services, ...}: {
  systemd.tmpfiles.rules = [
    "d /var/lib/media/metube 2775 1000 media -"
  ];

  virtualisation.oci-containers.containers.metube = {
    image = "ghcr.io/alexta69/metube:latest";
    pull = "newer";
    ports = ["127.0.0.1:${toString services.metube.port}:8081"];
    environment = {
      UID = "1000";
      GID = "986";
      DOWNLOAD_DIR = "/downloads";
      STATE_DIR = "/downloads/.metube";
      TEMP_DIR = "/downloads/.tmp";
      # iOS will not play webm/mkv, and the phone is the reason this exists.
      YTDL_OPTIONS = builtins.toJSON {
        format = "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b";
        merge_output_format = "mp4";
      };
    };
    volumes = ["/var/lib/media/metube:/downloads"];
  };

  # Same reasoning as invidious-companion: yt-dlp rots as YouTube changes, and
  # the default "missing" pull policy left that image untouched for 5 months.
  systemd.services.metube-update = {
    description = "Restart metube so it pulls a newer image";
    startAt = "weekly";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/systemctl restart podman-metube.service";
    };
  };
}
