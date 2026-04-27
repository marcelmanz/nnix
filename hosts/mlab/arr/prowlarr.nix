{
  _config,
  _pkgs,
  _lib,
  _services,
  ...
}: {
  sops.secrets."prowlarr_api" = {};

  services.prowlarr = {
    enable = true;
    openFirewall = true;
  };
}
