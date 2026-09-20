{
  config,
  lib,
  pkgs,
  services,
  ...
}: let
  # The v4 LAN is static, but the v6 prefix is ISP-delegated and has rotated
  # three times in five months, so pinning it would silently stop matching.
  # Read it off the on-link route instead; lanNetworks prints the group that
  # overrides the placeholder in settings.access_control.networks below.
  lanInterface = "enp1s0";
  lanIPv4 = "192.168.1.0/24";
  lanNetworksPath = "/var/lib/authelia-main/lan.yml";

  # Prints yaml, touches nothing; the unit below owns the writing. It cannot
  # run from authelia's own preStart: that service is confined to
  # RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX, and `ip` needs
  # AF_NETLINK, so it would silently yield the v4-only fallback.
  lanNetworks = pkgs.writeShellScript "authelia-lan-networks" ''
    set -euo pipefail
    prefix=$(${pkgs.iproute2}/bin/ip -6 route show dev ${lanInterface} proto kernel \
      | ${pkgs.coreutils}/bin/cut -d" " -f1 \
      | ${pkgs.gnugrep}/bin/grep -v "^fe80::" \
      | ${pkgs.coreutils}/bin/head -1 || true)
    echo "access_control:"
    echo "  networks:"
    echo "    - name: lan"
    echo "      networks:"
    echo "        - ${lanIPv4}"
    if [ -n "$prefix" ]; then
      echo "        - $prefix"
    fi
  '';

  # Every `protected` vhost in proxy.nix needs an entry here; without one
  # default_policy = "deny" returns 403 instead of the login page.
  # live.marcel.cool replaces the old livedj/streamcam entries: those hostnames
  # are plain 302s to it now (proxy.nix), and a redirect vhost has no
  # auth_request, so they never reach Authelia.
  protectedServices = [
    {
      domain = "home.marcel.cool";
      subject = ["group:admins"];
    }
    {
      domain = "qbit.marcel.cool";
      subject = ["group:admins"];
    }
    {
      domain = "sabnzbd.marcel.cool";
      subject = ["group:admins"];
    }
    {
      domain = "yt.marcel.cool";
      subject = ["group:youtube"];
    }
    {
      domain = "bailatube.marcel.cool";
      subject = ["group:youtube"];
    }
    {
      domain = "search.marcel.cool";
      subject = ["group:admins"];
    }
    {
      domain = "pinchflat.marcel.cool";
      subject = ["group:admins"];
    }
    {
      domain = "files.marcel.cool";
      subject = ["group:admins"];
    }
    {
      domain = "sync.marcel.cool";
      subject = ["group:admins"];
    }
    {
      domain = "bcsync.marcel.cool";
      subject = ["group:admins"];
    }
    {
      domain = "nitter.marcel.cool";
      subject = ["group:admins"];
    }
    {
      domain = "tags.marcel.cool";
      subject = ["group:admins"];
    }
    {
      domain = "live.marcel.cool";
      subject = ["group:admins"];
    }
  ];
in {
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

    # Both are written by preStart. settingsFiles are passed after the
    # generated config, so lan.yml is what actually sets the `lan` group.
    settingsFiles = ["/var/lib/authelia-main/jwks.yml" lanNetworksPath];

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
        remember_me = "1M";
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
        # To protect a new subdomain, add it to protectedServices or it will 401.
        default_policy = "deny";
        # Placeholder: lan.yml replaces this list at startup with the same v4
        # range plus whatever v6 prefix the link currently has. If that file is
        # missing or stale the worst case is a v4-only match, i.e. the normal
        # two_factor prompt - it can never widen the group.
        networks = [
          {
            name = "lan";
            networks = [lanIPv4];
          }
        ];
        # First match wins, so the lan copies go first: they only match clients
        # on the server's own link, and everyone else falls through to the
        # two_factor copies. Same domains and same group checks either way -
        # being on the LAN drops the TOTP code, not the password or the group.
        rules =
          (map (svc:
            svc
            // {
              policy = "one_factor";
              networks = ["lan"];
            })
          protectedServices)
          ++ (map (svc: svc // {policy = "two_factor";}) protectedServices);
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
    # lan.yml is a settingsFile, so it has to exist before authelia reads it.
    wants = ["authelia-lan-networks.service"];
    after = ["authelia-lan-networks.service"];

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

  # The prefix only changes when the ISP re-delegates, which is rare and gives
  # no notice, so poll for it rather than chase every address-change event on
  # an interface that gets a new temporary address all day. The comparison
  # means a steady prefix restarts nothing.
  systemd.services.authelia-lan-networks = {
    description = "Track the LAN IPv6 prefix Authelia treats as local";
    serviceConfig.Type = "oneshot";
    script = ''
      current=$(${lanNetworks})
      if [ "$current" = "$(${pkgs.coreutils}/bin/cat ${lanNetworksPath} 2>/dev/null)" ]; then
        exit 0
      fi
      printf '%s\n' "$current" > ${lanNetworksPath}
      ${pkgs.coreutils}/bin/chown authelia-main:authelia-main ${lanNetworksPath}
      ${pkgs.coreutils}/bin/chmod 600 ${lanNetworksPath}
      # --no-block because authelia-main is ordered after this unit: a
      # blocking restart would wait for a job that waits for us.
      ${pkgs.systemd}/bin/systemctl --no-block try-restart authelia-main.service
    '';
  };

  systemd.timers.authelia-lan-networks = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "15min";
    };
  };
}
