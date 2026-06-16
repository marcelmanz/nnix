{
  config,
  pkgs,
  lib,
  ...
}: let
  domain = "matrix.marcel.cool";
  serverName = "marcel.cool";
  synapsePort = 8008;
in {
  sops.secrets."matrix_postgres_password" = {
    owner = "matrix-synapse";
  };
  sops.secrets."matrix_registration_token" = {
    owner = "matrix-synapse";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/matrix 0755 root root -"
    "d /var/lib/matrix/postgresql 0755 root root -"
    "d /var/lib/matrix/media 0755 matrix-synapse matrix-synapse -"
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

  # Generate homeserver.yaml with secrets at runtime
  systemd.services.matrix-synapse = {
    after = ["postgresql.service"];
    requires = ["postgresql.service"];

    # Override the service to generate config with secrets
    serviceConfig = {
      ExecStartPre = let
        generateConfig = pkgs.writeScript "matrix-generate-config" ''          #!/bin/sh
          set -e
          PASSWORD=$(cat /run/secrets/matrix_postgres_password)
          TOKEN=$(cat /run/secrets/matrix_registration_token)
          CONFIG=/var/lib/matrix-synapse/homeserver.yaml

          cat > "$CONFIG" <<EOF
          server_name: ${serverName}
          public_baseurl: https://${domain}/
          listen_port: ${toString synapsePort}

          database:
            name: psycopg2
            args:
              dsn: "postgresql://matrix:$PASSWORD@127.0.0.1:5432/matrix"
              cp_min: 5
              cp_max: 10

          media_store_path: /var/lib/matrix/media
          registration_shared_secret: $TOKEN
          allow_guest_access: true
          enable_federation: true
          report_stats: false
          log_config: /etc/matrix-synapse/log.yaml
          EOF
        '';
      in [generateConfig];

      # Override ExecStart to use our generated config
      ExecStart = lib.mkForce "${pkgs.matrix-synapse}/bin/synapse_homeserver --config-path /var/lib/matrix-synapse/homeserver.yaml --keys-directory /var/lib/matrix-synapse";
    };
  };

  # Matrix Synapse server (settings will be overridden by our custom config)
  services.matrix-synapse = {
    enable = true;
    settings = {
      server_name = serverName;
      public_baseurl = "https://${domain}/";
      listen_port = synapsePort;
      media_store_path = "/var/lib/matrix/media";
      registration_shared_secret = config.sops.placeholder.matrix_registration_token;
      allow_guest_access = true;
      enable_federation = true;
    };
  };

  # Element Web (Matrix client) - served as static files
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = "marcel.cool";

    locations."/" = {
      root = "${pkgs.element-web}";
      index = "index.html";
      extraConfig = ''
        try_files $uri $uri/ /index.html =404;
      '';
    };
  };

  # Synapse API endpoint
  services.nginx.virtualHosts."synapse.${serverName}" = {
    forceSSL = true;
    useACMEHost = "marcel.cool";
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString synapsePort}";
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
    synapsePort
  ];
}
