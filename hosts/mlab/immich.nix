{
  _config,
  _lib,
  services,
  ...
}: {
  sops.secrets."immich_api" = {};

  services.immich = {
    enable = true;
    host = "0.0.0.0";
    port = services.immich.port;
  };
}
