{
  _config,
  _pkgs,
  lib,
  _services,
  ...
}: {
  sops.secrets."bazarr_api" = {};

  services.bazarr = {
    enable = true;
    group = "media";
    openFirewall = true;
  };

  systemd.services.bazarr.serviceConfig = {
    ReadWritePaths = ["/var/lib/media"];
    UMask = lib.mkForce "0002";
  };
}
