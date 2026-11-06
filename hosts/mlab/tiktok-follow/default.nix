{
  pkgs,
  services,
  ...
}: let
  script = ./tiktok-follow.py;
  python = "${pkgs.python3}/bin/python3";

  environment = {
    OFFTIKTOK_API_URL = "http://127.0.0.1:${toString services.offtiktokapi.port}";
    OFFTIKTOK_URL = services.offtiktok.href;
    OFFTIKTOK_PUBLIC_API_URL = services.offtiktokapi.href;
  };

  serviceConfig = {
    User = "tiktok-follow";
    Group = "tiktok-follow";
    StateDirectory = "tiktok-follow";
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
  users.users.tiktok-follow = {
    isSystemUser = true;
    group = "tiktok-follow";
  };
  users.groups.tiktok-follow = {};

  systemd.services.tiktok-follow = {
    description = "TikTok profile follower web UI (tiktok.marcel.cool)";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    after = ["network-online.target" "offtiktokapi.service"];
    path = [pkgs.yt-dlp];
    inherit environment;
    serviceConfig =
      serviceConfig
      // {
        ExecStart = "${python} ${script} serve ${toString services.tiktok.port}";
        Restart = "always";
        RestartSec = "5";
      };
  };

  systemd.services.tiktok-follow-check = {
    description = "Check followed TikTok profiles and save new videos to offtiktok";
    wants = ["network-online.target"];
    after = ["network-online.target" "offtiktokapi.service"];
    path = [pkgs.yt-dlp];
    inherit environment;
    serviceConfig =
      serviceConfig
      // {
        Type = "oneshot";
        ExecStart = "${python} ${script} check";
      };
  };

  systemd.timers.tiktok-follow-check = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "1h";
      Persistent = true;
    };
  };
}
