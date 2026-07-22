{
  config,
  pkgs,
  _lib,
  services,
  ...
}: {
  environment.systemPackages = with pkgs; [
    attic-client
    attic-server
  ];

  users.users.atticd = {
    isSystemUser = true;
    group = "atticd";
  };
  users.groups.atticd = {};

  sops.secrets."attic_env" = {
    owner = "atticd";
    group = "atticd";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/atticd 0750 atticd atticd -"
  ];

  services.postgresql = {
    ensureDatabases = ["atticd"];
    ensureUsers = [
      {
        name = "atticd";
        ensureDBOwnership = true;
      }
    ];
  };

  services.atticd = {
    enable = true;
    environmentFile = config.sops.secrets.attic_env.path;
    settings = {
      # Dynamically grab the port from your main file's services block
      listen = "[::]:${toString services.attic.port}";
      # database.url = "postgresql://atticd?host=/run/postgresql";
      database.url = "postgresql://atticd@%2Frun%2Fpostgresql/atticd";
      storage = {
        type = "local";
        path = "/var/lib/atticd";
      };
      chunking = {
        nar-size-threshold = 65536;
        min-size = 16384;
        avg-size = 65536;
        max-size = 262144;
      };
    };
  };
}
