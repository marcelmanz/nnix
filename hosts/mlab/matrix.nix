{
  config,
  pkgs,
  lib,
  ...
}: let
  domain = "matrix.marcel.cool";
  serverName = "marcel.cool";
  synapsePort = 8088;
  baseUrl = "https://${domain}/";

  # Element config for the web client
  clientConfig = {
    "m.server_name" = serverName;
    "m.homeserver" = {
      base_url = baseUrl;
      server_name = serverName;
    };
    "m.identityserver" = {
      base_url = "https://vector.im";
    };
  };
in {
  # SOPS secrets for Matrix
  sops.secrets."matrix_registration_token" = {
    owner = "matrix-synapse";
  };

  # SOPS template for registration token config file
  sops.templates."matrix-registration-token" = {
    content = "registration_shared_secret: ${config.sops.placeholder.matrix_registration_token}";
    owner = "matrix-synapse";
  };

  # PostgreSQL database for Matrix
  services.postgresql = {
    enable = true;
    ensureDatabases = ["matrix"];
    ensureUsers = [
      {
        name = "matrix";
        ensureDBOwnership = true;
      }
    ];
    # Force trust authentication for matrix user to avoid peer auth issues
    authentication = lib.mkForce ''
      local   all             all                                     trust
      host    all             all             127.0.0.1/32            trust
      host    all             all             ::1/128                 trust
      local   replication     all                                     trust
      host    replication     all             127.0.0.1/32            trust
      host    replication     all             ::1/128                 trust
    '';
  };

  # Matrix Synapse server
  services.matrix-synapse = {
    enable = true;

    # Server identification
    settings = {
      server_name = serverName;
      public_baseurl = baseUrl;

      # Database configuration (use socket for trust auth)
      database = {
        name = "psycopg2";
        args = {
          user = "matrix";
          database = "matrix";
          host = "/run/postgresql";
          cp_min = 5;
          cp_max = 10;
        };
      };

      # Media storage
      media_store_path = "/var/lib/matrix-synapse/media";

      # Registration
      enable_registration = true;
      enable_registration_without_verification = true;

      # Guest access and federation
      allow_guest_access = true;
      enable_federation = true;

      # Reporting
      report_stats = false;

      # HTTP listener on localhost
      listeners = [
        {
          port = synapsePort;
          bind_addresses = ["127.0.0.1"];
          type = "http";
          tls = false;
          x_forwarded = true;
          resources = [
            {
              names = ["client" "federation"];
              compress = true;
            }
          ];
        }
      ];

      # Log configuration
      log_config = "/var/lib/matrix-synapse/log.yaml";
    };

    # Extra config files for secrets
    extraConfigFiles = [
      # Registration token from SOPS
      (config.sops.templates."matrix-registration-token".path)
    ];

    # Generate log config
    log = {
      version = 1;
      formatters.journal_fmt.format = "%(name)s: [%(request)s] %(message)s";
      handlers.journal = {
        class = "systemd.journal.JournalHandler";
        formatter = "journal_fmt";
      };
      root = {
        level = "INFO";
        handlers = ["journal"];
      };
      disable_existing_loggers = false;
    };
  };

  # Ensure matrix-synapse starts after PostgreSQL
  # Also fix database collation if needed
  systemd.services.matrix-synapse = {
    after = ["postgresql.service"];
    requires = ["postgresql.service"];
    # Fix database collation before starting
    preStart = ''
      # Check if database has wrong collation and recreate if needed
      if ${pkgs.postgresql}/bin/psql -U matrix -d matrix -c "SHOW lc_collate" | grep -q "en_US"; then
        echo "Recreating matrix database with correct collation..."
        ${pkgs.postgresql}/bin/psql -U postgres -c "DROP DATABASE matrix;"
        ${pkgs.postgresql}/bin/psql -U postgres -c "CREATE DATABASE matrix WITH OWNER matrix TEMPLATE template0 LC_COLLATE = 'C' LC_CTYPE = 'C';"
      fi
    '';
  };

  # nginx configuration for Matrix
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = "marcel.cool";

    # Element Web
    locations."/" = {
      root = pkgs.element-web;
      index = "index.html";
      extraConfig = ''
        try_files $uri $uri/ /index.html =404;
      '';
    };

    # Custom Element config.json
    locations."/config.json" = {
      extraConfig = ''
        return 200 '${lib.toJSON {
          default_server_config = clientConfig;
        }}';
      '';
    };

    # Proxy Matrix API to Synapse (use regex to match all /_matrix/* paths)
    locations."~ ^/_matrix/" = {
      proxyPass = "http://127.0.0.1:${toString synapsePort}";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
      '';
    };

    # Proxy Synapse client endpoints
    locations."/_synapse/client" = {
      proxyPass = "http://127.0.0.1:${toString synapsePort}";
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
      '';
    };
  };

  # Firewall - only allow HTTP/HTTPS
  networking.firewall.allowedTCPPorts = [80 443];
}

