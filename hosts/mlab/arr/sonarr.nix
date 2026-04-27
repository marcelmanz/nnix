{
  _config,
  _pkgs,
  lib,
  _services,
  ...
}: {
  sops.secrets."sonarr_api" = {};

  services.sonarr = {
    enable = true;
    openFirewall = true;
  };

  users.users.sonarr = {
    isSystemUser = true;
    group = "sonarr";
    extraGroups = ["media"];
  };
  users.groups.sonarr = {};

  systemd.services.sonarr.serviceConfig = {
    ReadWritePaths = ["/var/lib/media"];
    UMask = lib.mkForce "0002";
  };
}
