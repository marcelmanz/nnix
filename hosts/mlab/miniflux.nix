{
  config,
  _lib,
  services,
  ...
}: {
  services.miniflux = {
    enable = true;
    config = {
      LISTEN_ADDR = "127.0.0.1:${toString services.miniflux.port}";
      BASE_URL = services.miniflux.href;
      POLLING_FREQUENCY = "15"; # minutes
      SCHEDULER_ROUND_ROBIN_MIN_INTERVAL = "15"; # minutes
      BATCH_SIZE = "500";
      WORKER_POOL_SIZE = "10";
    };
    adminCredentialsFile = config.sops.secrets.miniflux_admin_credentials.path;
  };

  sops.secrets."miniflux_admin_credentials" = {};
  sops.secrets."miniflux_api" = {};
}
