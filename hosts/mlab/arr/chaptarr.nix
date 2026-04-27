{
  config,
  _pkgs,
  _lib,
  _services,
  ...
}: {
  systemd.tmpfiles.rules = [
    "d /var/lib/chaptarr 0775 chaptarr media -"
  ];

  virtualisation.oci-containers.containers.chaptarr = {
    image = "robertlordhood/chaptarr:latest";
    volumes = [
      "/var/lib/chaptarr:/config"
      "/var/lib/media/books:/var/lib/media/books"
      "/var/lib/media/audiobooks:/var/lib/media/audiobooks"
      "/var/lib/media/downloads:/var/lib/media/downloads"
      "/var/lib/media/books/import:/var/lib/media/books/import"
    ];
    environment = {
      TZ = config.time.timeZone;
      PUID = "950"; # static chaptarr user UID
      PGID = "986"; # system's 'media' group GID
      UMASK = "002"; # allows CWA to move files
    };
    extraOptions = [
      "--network=host"
      "--init"
    ];
  };

  users.users.chaptarr = {
    isSystemUser = true;
    group = "chaptarr";
    extraGroups = ["media"];
    uid = 950;
  };
  users.groups.chaptarr = {
    gid = 950;
  };
}
