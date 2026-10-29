{
  _config,
  _lib,
  services,
  ...
}: {
  sops.secrets."navidrome_salt" = {};
  sops.secrets."navidrome_token" = {};

  services.navidrome = {
    enable = true;
    user = "navidrome";
    group = "navidrome";
    settings = {
      DataFolder = "/var/lib/navidrome";
      Address = "0.0.0.0";
      Port = services.navidrome.port;
      MusicFolder = "/var/lib/media/music";
      DB = {
        Type = "postgres";
        Host = "/run/postgresql";
        User = "navidrome";
        Database = "navidrome";
      };
    };
  };

  users.users.navidrome = {
    isSystemUser = true;
    group = "navidrome";
    extraGroups = ["slskd"];
    home = "/var/lib/navidrome";
    createHome = true;
  };
  users.groups.navidrome = {};

  systemd.services.navidrome.serviceConfig.BindReadOnlyPaths = [
    "/var/lib/media/music"
    # Uncomment with the tmpfiles rule below to expose slskd's share read-only to Navidrome only.
    # "/var/lib/slskd/music/share:/var/lib/media/music/slskd"
  ];

  # Mount point for the slskd bind above; the parent is read-only inside the unit, so systemd can't create it.
  # systemd.tmpfiles.rules = [
  #   "d /var/lib/media/music/slskd 0755 root root -"
  # ];
}
