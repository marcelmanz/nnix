{
  config,
  pkgs,
  lib,
  ...
}: let
  livekitDomain = "livekit.marcel.cool";
in {
  sops.secrets."coturn_secret" = {};

  services.livekit = {
    enable = true;
    keyFile = config.sops.templates."livekit-secrets".path;
    redis = {
      createLocally = true;
      host = "127.0.0.1";
      port = 6379;
    };
    settings = {
      # Main TCP port for RoomService and RTC endpoint
      port = 7880;
      redis = {
        address = "127.0.0.1:6379";
      };

      logging = {
        level = "info";
      };

      room = {
        max_participants = 50;
        empty_timeout = 300;
        departure_timeout = 20;
      };

      rtc = {
        port_range_start = 50000;
        port_range_end = 60000;

        turn_servers = [
          {
            host = "matrix.marcel.cool";
            port = 3478;
            protocol = "udp";
            # Shared secret for TURN server authentication
            secret = config.sops.placeholder.coturn_secret;
          }
        ];
      };
    };
  };

  services.nginx.virtualHosts.${livekitDomain} = {
    forceSSL = true;
    useACMEHost = "marcel.cool";

    locations."/" = {
      proxyPass = "http://localhost:7880";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $http_connection;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
      '';
    };
  };

  networking.firewall.allowedTCPPorts = [
    80 # nginx HTTP
    443 # nginx HTTPS
    7880 # LiveKit HTTP
    7881 # LiveKit API
  ];

  networking.firewall.allowedUDPPortRanges = [
    {
      from = 50000;
      to = 60000;
    }
  ];

  # Prometheus exporter for LiveKit monitoring
  # (optional - uncomment if you want monitoring)
  # services.prometheus.exporters.livekit = {
  #   enable = true;
  #   port = 9000;
  # };
}

