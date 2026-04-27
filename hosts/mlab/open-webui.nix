{
  _config,
  _lib,
  services,
  ...
}: {
  services.open-webui = {
    enable = true;
    host = "0.0.0.0";
    port = services.openwebui.port;
  };
}
