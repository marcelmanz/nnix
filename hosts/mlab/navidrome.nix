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
      MusicFolder = "/var/lib/slskd/music/share";
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
    "/var/lib/slskd/music/share"
  ];
}
