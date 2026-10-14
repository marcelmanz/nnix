{
  config,
  pkgs,
  _lib,
  services,
  ...
}: {
  sops.secrets."searxng_secret_key" = {};
  sops.templates."searxng.env" = {
    content = ''
      SEARX_SECRET_KEY=${config.sops.placeholder.searxng_secret_key}
    '';
  };

  services.searx = {
    enable = true;
    package = pkgs.searxng;
    redisCreateLocally = true;
    environmentFile = config.sops.templates."searxng.env".path;

    settings = {
      server = {
        port = services.searxng.port;
        # 0.0.0.0 so podman containers reach it; 8084 stays firewall-closed.
        bind_address = "0.0.0.0";
        secret_key = "@SEARX_SECRET_KEY@";
      };

      search = {
        formats = ["html" "json"]; # openwebui requires json output
      };
    };
  };
}
