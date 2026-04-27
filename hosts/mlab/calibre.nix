{
  config,
  _lib,
  _services,
  ...
}: {
  systemd.tmpfiles.rules = [
    # Books & Calibre Stack
    # We give 'calibre' primary ownership, but 'media' group rwx access
    "d /var/lib/media/books 0775 calibre media -"
    "d /var/lib/media/books/import 2775 calibre media -"
    "d /var/lib/calibre-web-automated/config 0775 calibre media -"
  ];

  virtualisation.oci-containers.containers.calibre-web-automated = {
    image = "crocodilestick/calibre-web-automated:latest";
    volumes = [
      "/var/lib/calibre-web-automated/config:/config"
      "/var/lib/media/books:/calibre-library"
      "/var/lib/media/books/import:/cwa-book-ingest"
    ];
    environment = {
      PUID = "951";
      PGID = "986";
      TZ = config.time.timeZone;
      DOCKER_MODS = "linuxserver/mods:universal-calibre";
    };
    extraOptions = [
      "--network=host"
      "--no-healthcheck"
    ];
  };

  users.users.calibre = {
    isSystemUser = true;
    group = "calibre";
    extraGroups = ["media"];
    uid = 951;
  };
  users.groups.calibre = {
    gid = 951;
  };
}
