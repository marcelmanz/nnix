{
  config,
  _pkgs,
  _lib,
  services,
  ...
}: {
  sops.secrets."vaultwarden_env" = {};
  services.vaultwarden = {
    enable = true;
    dbBackend = "postgresql";
    environmentFile = config.sops.secrets."vaultwarden_env".path;
    config = {
      DOMAIN = services.vaultwarden.href;
      ROCKET_PORT = services.vaultwarden.port;
      ROCKET_ADDRESS = "127.0.0.1";
      DATABASE_URL = "postgresql://vaultwarden@%2Frun%2Fpostgresql/vaultwarden";

      SIGNUPS_ALLOWED = false;
      INVITATIONS_ALLOWED = false;
      SHOW_PASSWORD_HINT = false;
    };
  };
  services.postgresql = {
    ensureDatabases = ["vaultwarden"];
    ensureUsers = [
      {
        name = "vaultwarden";
        ensureDBOwnership = true;
      }
    ];
  };
}
