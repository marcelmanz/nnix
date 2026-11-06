{
  config,
  pkgs,
  ...
}: let
  hardening = {
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateDevices = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    ProtectClock = true;
    ProtectHostname = true;
    ProtectProc = "invisible";
    ProcSubset = "pid";
    CapabilityBoundingSet = "";
    RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    LockPersonality = true;
    RemoveIPC = true;
    SystemCallArchitectures = "native";
    SystemCallFilter = ["@system-service" "~@privileged" "~@resources"];
    UMask = "0077";
  };
in {
  systemd.services.offtiktok = {
    description = "offtiktok frontend (Next.js on loopback port 3010)";
    wantedBy = ["multi-user.target"];
    after = ["network.target"];
    serviceConfig =
      hardening
      // {
        Type = "simple";
        User = "offtiktok";
        ExecStart = "${pkgs.offtiktok}/bin/offtiktok";
        CacheDirectory = "offtiktok";
        Restart = "always";
        RestartSec = "5";
      };
  };

  systemd.services.offtiktokapi = {
    description = "offtiktok backend (Express/Prisma on port 2000)";
    wantedBy = ["multi-user.target"];
    after = ["network.target"];
    serviceConfig =
      hardening
      // {
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
