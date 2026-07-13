{...}: {
  sops.secrets."jellyfin_api" = {};

  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };
  systemd.services.jellyfin.serviceConfig = {
    CPUQuota = "800%";
    MemoryHigh = "18G";
  };
  users.users.jellyfin.extraGroups = [
    "render"
    "video"
    "media"
    "slskd"
  ];
}
