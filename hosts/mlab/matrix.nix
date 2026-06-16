{
  config,
  pkgs,
  lib,
  ...
}: let
  domain = "matrix.marcel.cool";
  callDomain = "call.matrix.marcel.cool";

  elementCallPackage = pkgs.element-call;

  clientConfig = {
    "m.homeserver" = {
      "base_url" = "https://${domain}/";
      "server_name" = "marcel.cool";
    };
    "m.identityserver" = {
      "base_url" = "https://vector.im";
    };
    "m.server_name" = "marcel.cool";
    "widget_url" = "https://${callDomain}/";
  };

  elementCallConfig = pkgs.writeText "element-call-config.json" ''
    {
      "default_server_config": {
        "m.homeserver": {
          "base_url": "https://${domain}/",
          "server_name": "marcel.cool"
        }
      },
      "features": {
        "feature_use_device_session_member_events": true
      },
      "livekit": {
        "livekit_service_url": "https://livekit.element.io"
      },
      "matrix_rtc_session": {
        "wait_for_key_rotation_ms": 5000,
        "membership_event_expiry_ms": 7200000,
        "delayed_leave_event_delay_ms": 90000,
        "delayed_leave_event_restart_ms": 4000,
        "delayed_leave_event_restart_local_timeout_ms": 10000,
        "network_error_retry_ms": 100
      }
    }
  '';

  wellKnownConfig = lib.toJSON {
    "m.homeserver" = {
      "base_url" = "https://${domain}/";
    };
    "m.identity_server" = {
      "base_url" = "https://vector.im/";
    };
    "org.matrix.msc2965.authentication" = {
      "oidc_discovery_uri" = "https://auth.marcel.cool/.well-known/openid-configuration";
    };
    "org.matrix.msc4171.element_call" = {
      "url" = "https://${callDomain}/";
    };
  };

  matrixApiProxyConfig = "proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto https; proxy_set_header X-Forwarded-Host $host; proxy_connect_timeout 3s; proxy_send_timeout 15m; proxy_read_timeout 15m; error_page 502 503 504 = @maintenance;";

  elementCallProxyConfig = "proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto https;";
in {
  # Matrix Synapse server
  services.matrix-synapse = {
    enable = true;

    settings = {
      enable_registration = false;
      server_name = "marcel.cool";
      listeners = [
        {
          port = 8088;
          bind_addresses = ["127.0.0.1"];
          type = "http";
          tls = false;
          resources = [
            {
              names = ["client"];
              compress = true;
            }
            {
              names = ["federation"];
              compress = false;
            }
          ];
        }
      ];
      use_appservice_welcome_email = false;

      # MatrixRTC with LiveKit
      matrix_rtc_session = {
        livekit_service_url = "http://localhost:8081";
      };
    };

    # PostgreSQL database
    settings.database = {
      name = "psycopg2";
      args = {
        database = "matrix";
        user = "matrix";
        host = "/run/postgresql";
      };
    };
    extraConfigFiles = [
      (pkgs.writeText "synapse-log-config.yaml" ''
        root: /var/log/synapse
      '')
    ];
  };

  # nginx configuration for Matrix
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = "marcel.cool";

    # Element Web
    locations."/" = {
      root = pkgs.element-web;
      index = "index.html";
      extraConfig = "try_files $uri $uri/ /index.html =404;";
    };

    # Custom Element config.json
    locations."/config.json" = {
      extraConfig = "add_header Content-Type application/json; return 200 '${lib.toJSON {default_server_config = clientConfig;}}';";
    };

    # .well-known/matrix/client for client discovery
    locations."/.well-known/matrix/client" = {
      extraConfig = "add_header Content-Type application/json; add_header Access-Control-Allow-Origin *; return 200 '${wellKnownConfig}';";
    };

    # Proxy Matrix API to Synapse
    locations."~ ^/_matrix/" = {
      proxyPass = "http://127.0.0.1:8088";
      proxyWebsockets = true;
      extraConfig = matrixApiProxyConfig;
    };

    # Proxy Synapse client endpoints
    locations."/_synapse/client" = {
      proxyPass = "http://127.0.0.1:8088";
      extraConfig = elementCallProxyConfig;
    };
  };

  # coturn TURN server for 1:1 calls
  services.coturn = {
    enable = true;
    listening-ips = ["0.0.0.0" "::"];
    listening-port = 3478;
    min-port = 49152;
    max-port = 49200;
    static-auth-secret = "coturn-secret-change-me-in-production";
  };

  # lk-jwt-service for MatrixRTC (Element Call)
  services.lk-jwt-service = {
    enable = true;
    livekitUrl = "wss://livekit.element.io";
    keyFile = config.sops.templates."livekit-secrets".path;
    port = 8090;
  };

  # Add coturn TURN config to Synapse
  services.matrix-synapse.settings.turn_servers = [
    {
      urls = ["turn:${domain}:3478" "turn:${domain}:3478?transport=udp"];
      username = "turn_user";
      credential = "coturn-secret-change-me-in-production";
    }
  ];

  # nginx for Element Call
  services.nginx.virtualHosts.${callDomain} = {
    forceSSL = true;
    useACMEHost = "matrix.marcel.cool";
    locations."/" = {
      root = elementCallPackage;
      extraConfig = "try_files $uri $uri/ /index.html =404; ${elementCallProxyConfig};";
    };
    locations."/config.json" = {
      root = "/etc/element-call";
      extraConfig = "add_header Content-Type application/json;";
    };
  };

  # Firewall - allow coturn ports
  networking.firewall.allowedTCPPorts = [80 443 3478];
  networking.firewall.allowedUDPPorts = [3478];
  networking.firewall.allowedUDPPortRanges = [
    {
      from = 49152;
      to = 49200;
    }
  ];

  # Deploy Element Call config file
  environment.etc."element-call/config.json".source = elementCallConfig;
}
