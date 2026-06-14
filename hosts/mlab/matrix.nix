{
  config,
  pkgs,
  services,
  lib,
  ...
}: let
  domain = "matrix.marcel.cool";
  serverName = "marcel.cool";
in {
  sops.secrets."matrix_postgres_password" = {};
  sops.secrets."matrix_registration_token" = {};
  sops.secrets."matrix_turn_credentials" = {};

  sops.templates."matrix-db.env".content = ''
    POSTGRES_DB=matrix
    POSTGRES_USER=matrix
    POSTGRES_PASSWORD=${config.sops.placeholder.matrix_postgres_password}
  '';

  systemd.tmpfiles.rules = [
    "d /var/lib/matrix 0755 root root -"
    "d /var/lib/matrix/postgresql 0755 root root -"
    "d /var/lib/matrix/media 0755 matrix matrix -"
  ];

  # PostgreSQL database for Matrix
  services.postgresql = {
    ensureDatabases = ["matrix"];
    ensureUsers = [
      {
        name = "matrix";
        ensureDBOwnership = true;
      }
    ];
  };

  # Matrix Synapse server
  services.matrix-synapse = {
    enable = true;
    settings = {
      server_name = serverName;
      public_baseurl = "https://${domain}/";

      listen_port = 8008;

      database = {
        name = "psycopg2";
        args = {
          user = "matrix";
          database = "matrix";
          password = config.sops.placeholder.matrix_postgres_password;
          host = "localhost";
          cp_min = 5;
          cp_max = 10;
        };
      };

      media_store_path = "/var/lib/matrix/media";

      registration_shared_secret = config.sops.placeholder.matrix_registration_token;

      # Turn credentials for VoIP (optional, for better NAT handling)
      turn_uris = [
        "turn:${domain}?transport=udp"
        "turn:${domain}?transport=tcp"
      ];
      turn_shared_secret = config.sops.placeholder.matrix_turn_credentials;

      # Allow guest access for public rooms
      allow_guest_access = true;

      # Enable federation
      enable_federation = true;

      # Log settings
      log_config = "/etc/matrix-synapse/log.yaml";
    };
  };

  # Element Web (Matrix client)
  services.element-web = {
    enable = true;
    config = {
      default_server_config = {
        "m.server" = "${serverName}:${toString services.matrix-synapse.settings.listen_port}";
      };
      default_federate = true;
      default_theme = "light";
      room_directory = {
        enabled = true;
      };
    };
  };

  # Proxy configuration for Matrix
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = "marcel.cool";
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString services.element-web.port}";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
      '';
    };
  };

  # Synapse API endpoint
  services.nginx.virtualHosts."synapse.${serverName}" = {
    forceSSL = true;
    useACMEHost = "marcel.cool";
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString services.matrix-synapse.settings.listen_port}";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
      '';
    };
  };

  # Firewall rules
  networking.firewall.allowedTCPPorts = [
    8008 # Synapse
  ];

  # Systemd service dependencies
  systemd.services.matrix-synapse = {
    after = ["postgresql.service"];
    requires = ["postgresql.service"];
  };
}
