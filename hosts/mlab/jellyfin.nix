{...}: {
  sops.secrets."jellyfin_api" = {};

  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  users.users.jellyfin.extraGroups = [
    "render"
    "video"
    "media"
    "slskd"
  ];
}
