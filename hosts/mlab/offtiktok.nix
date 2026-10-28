{
  config,
  pkgs,
  ...
}: {
  systemd.services.offtiktok = {
    description = "offtiktok frontend (Next.js on loopback port 3010)";
    wantedBy = ["multi-user.target"];
    after = ["network.target"];
    serviceConfig = {
      Type = "simple";
      User = "offtiktok";
      ExecStart = "${pkgs.offtiktok}/bin/offtiktok";
      Restart = "always";
      RestartSec = "5";
    };
  };

  systemd.services.offtiktokapi = {
    description = "offtiktok backend (Express/Prisma on port 2000)";
    wantedBy = ["multi-user.target"];
    after = ["network.target"];
    serviceConfig = {
      Type = "simple";
      User = "offtiktokapi";
      ExecStart = "${pkgs.offtiktokapi}/bin/offtiktokapi";
      # the sqlite db lives in the unit's StateDirectory
      Environment = "DATABASE_URL=file:/var/lib/offtiktokapi/offtiktok.db";
      StateDirectory = "offtiktokapi";
      Restart = "always";
      RestartSec = "5";
    };
  };

  users.users.offtiktok = {
    isSystemUser = true;
    group = "offtiktok";
  };
  users.groups.offtiktok = {};

  users.users.offtiktokapi = {
    isSystemUser = true;
    group = "offtiktokapi";
  };
  users.groups.offtiktokapi = {};
}
