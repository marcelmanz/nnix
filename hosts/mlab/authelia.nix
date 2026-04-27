{
  config,
  lib,
  pkgs,
  services,
  ...
}: {
  sops.secrets."authelia_jwt_secret" = {owner = "authelia-main";};
  sops.secrets."authelia_session_secret" = {owner = "authelia-main";};
  sops.secrets."authelia_storage_encryption_key" = {owner = "authelia-main";};
  sops.secrets."authelia_oidc_hmac_secret" = {owner = "authelia-main";};
  sops.secrets."authelia_oidc_issuer_key" = {owner = "authelia-main";};
  sops.secrets."authelia_tailscale_client_secret" = {owner = "authelia-main";};
  sops.secrets."authelia_admin_password" = {owner = "authelia-main";};

  sops.templates."authelia-env" = {
    content = ''
      AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET=${config.sops.placeholder.authelia_jwt_secret}
      AUTHELIA_SESSION_SECRET=${config.sops.placeholder.authelia_session_secret}
      AUTHELIA_STORAGE_ENCRYPTION_KEY=${config.sops.placeholder.authelia_storage_encryption_key}
      AUTHELIA_IDENTITY_PROVIDERS_OIDC_HMAC_SECRET=${config.sops.placeholder.authelia_oidc_hmac_secret}
    '';
    owner = "authelia-main";
  };

  sops.templates."authelia-users" = {
    content = ''
      users:
        authelia:
          displayname: "Authelia Admin"
          password: "${config.sops.placeholder.authelia_admin_password}"
          email: "authelia@auth.marcel.cool"
          groups:
            - admins
    '';
    owner = "authelia-main";
  };

  services.authelia.instances.main = {
    enable = true;
    secrets.manual = true;

    settingsFiles = ["/var/lib/authelia-main/jwks.yml"];

    settings = {
      theme = "dark";
      server.address = "tcp://0.0.0.0:${toString services.auth.port}";
      server.buffers.read = 16384;
      server.buffers.write = 16384;

      session = {
        name = "authelia_session";
        cookies = [
          {
            domain = "marcel.cool";
            authelia_url = "https://auth.marcel.cool";
            default_redirection_url = "https://home.marcel.cool";
          }
        ];
      };

      access_control = {
        default_policy = "one_factor";
      };

      notifier = {
        filesystem = {
          filename = "/var/lib/authelia-main/notification.txt";
        };
      };

      authentication_backend.file.path = config.sops.templates."authelia-users".path;
      storage.local.path = "/var/lib/authelia-main/db.sqlite3";

      identity_providers.oidc = {
        clients = [
          {
            client_id = "tailscale";
            client_name = "Tailscale";
            client_secret = "$pbkdf2-sha512$310000$nGGxzhdyKtIYCeeywAwYGA$IhOBt2rIZpnMhGb9.LuetMaU8TMyqZCtIdqepFJbzss34G8OC1ZP.a9m131ccd95ThKqOCb3hzMP8.ypTU0E/w";
            public = false;
            authorization_policy = "one_factor";
            redirect_uris = ["https://login.tailscale.com/a/oauth_response"];
            scopes = ["openid" "profile" "email"];
            userinfo_signed_response_alg = "none";
          }
        ];
      };
    };
  };

  systemd.services.authelia-main = {
    serviceConfig = {
      EnvironmentFile = [config.sops.templates."authelia-env".path];
    };

    preStart = lib.mkBefore ''
      ${pkgs.coreutils}/bin/cat <<EOF > /var/lib/authelia-main/jwks.yml
      identity_providers:
        oidc:
          jwks:
            - key_id: "tailscale-key"
              algorithm: "RS256"
              use: "sig"
              key: |
      EOF
      ${pkgs.gnused}/bin/sed 's/^/          /' ${config.sops.secrets.authelia_oidc_issuer_key.path} >> /var/lib/authelia-main/jwks.yml
      ${pkgs.coreutils}/bin/chmod 600 /var/lib/authelia-main/jwks.yml
    '';
  };
}
