{
  _config,
  _pkgs,
  lib,
  _services,
  ...
}: {
  sops.secrets."radarr_api" = {};

  services.radarr = {
    enable = true;
    group = "media";
    openFirewall = true;
  };

  users.users.radarr = {
    extraGroups = ["media"];
  };

  systemd.services.radarr.serviceConfig = {
    ReadWritePaths = ["/var/lib/media"];
    UMask = lib.mkForce "0002";
  };
}
