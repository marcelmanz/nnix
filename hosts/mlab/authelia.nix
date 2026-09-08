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
          email: "authelia@marcel.cool"
          groups:
            - admins
            - youtube
        metube:
          displayname: "metube"
          password: "${config.sops.placeholder.ytify_user_password}"
          email: "metube@marcel.cool"
          groups:
            - youtube
    '';
    owner = "authelia-main";
  };

  services.authelia.instances.main = {
    enable = true;
    secrets.manual = true;

    settingsFiles = ["/var/lib/authelia-main/jwks.yml"];

    settings = {
      theme = "dark";
      # Enroll at auth.marcel.cool -> Methods.
      default_2fa_method = "totp";
      totp.issuer = "marcel.cool";
      server.address = "tcp://127.0.0.1:${toString services.auth.port}"; # nginx fronts this
      server.buffers.read = 16384;
      server.buffers.write = 16384;

      session = {
        name = "authelia_session";
        expiration = "1M";
        inactivity = "1w";
        remember_me_duration = "1M";
        cookies = [
          {
            domain = "marcel.cool";
            authelia_url = "https://auth.marcel.cool";
            default_redirection_url = "https://home.marcel.cool";
          }
        ];
      };

      access_control = {
        # Deny by default; every protected service gets an explicit rule below.
        # To protect a new subdomain, add a rule here too or it will 401.
        default_policy = "deny";
        rules = [
          # Every `protected` vhost in proxy.nix needs a rule here; without one
          # default_policy = "deny" returns 403 instead of the login page.
          {
            domain = "home.marcel.cool";
            policy = "two_factor";
            subject = ["group:admins"];
          }
          {
            domain = "qbit.marcel.cool";
            policy = "two_factor";
            subject = ["group:admins"];
          }
          {
            domain = "yt.marcel.cool";
            policy = "two_factor";
            subject = ["group:youtube"];
          }
          {
            domain = "bailatube.marcel.cool";
            policy = "two_factor";
            subject = ["group:youtube"];
          }
          {
            domain = "search.marcel.cool";
            policy = "two_factor";
            subject = ["group:admins"];
          }
          {
            domain = "pinchflat.marcel.cool";
            policy = "two_factor";
            subject = ["group:admins"];
          }
          {
            domain = "sync.marcel.cool";
            policy = "two_factor";
            subject = ["group:admins"];
          }
          {
            domain = "bcsync.marcel.cool";
            policy = "two_factor";
            subject = ["group:admins"];
          }
          {
            domain = "nitter.marcel.cool";
            policy = "two_factor";
            subject = ["group:admins"];
          }
          {
            domain = "livedj.marcel.cool";
            policy = "two_factor";
            subject = ["group:admins"];
          }
          {
            domain = "streamcam.marcel.cool";
            policy = "two_factor";
            subject = ["group:admins"];
          }
        ];
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
            authorization_policy = "two_factor";
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
