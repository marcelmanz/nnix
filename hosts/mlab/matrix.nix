{
  config,
  pkgs,
  lib,
  ...
}: let
  domain = "matrix.marcel.cool";
  callDomain = "call.matrix.marcel.cool";
  serverName = "marcel.cool";

  clientConfig = {
    "m.homeserver" = {
      "base_url" = "https://${domain}/";
      "server_name" = serverName;
    };
    "m.identityserver" = {
      "base_url" = "https://vector.im";
    };
    "m.server_name" = serverName;
    "widget_url" = "https://${callDomain}/";
    "org.matrix.msc4143.rtc_foci" = [{
      type = "livekit";
      livekit_service_url = "https://${domain}/livekit/jwt";
    }];
  };

in {
  imports = [
    ./cinny.nix
    # ./element.nix
  ];

  sops.secrets."coturn_secret" = {};

  services.matrix-synapse = {
    enable = true;
    settings = {
      enable_registration = false;
      server_name = serverName;
      experimental_features.msc4143_enabled = true;
      listeners = [{
        port = 8088;
        bind_addresses = ["127.0.0.1"];
        type = "http";
        tls = false;
        resources = [{ names = ["client" "federation"]; compress = true; }];
      }];
      use_appservice_welcome_email = false;
      matrix_rtc = {
        transports = [{
          type = "livekit";
          livekit_service_url = "https://${domain}/livekit/jwt";
        }];
      };
      database = { name = "psycopg2"; args = { database = "matrix"; user = "matrix"; host = "/run/postgresql"; }; };
    };
  };

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = "marcel.cool";
    locations."/_matrix/client/versions" = {
      proxyPass = "http://127.0.0.1:8088";
      extraConfig = ''
        # ponytail: sub_filter module unavailable, Synapse doesn't advertise mRtc natively
        # Element Call discovers transport via .well-known/matrix/client org.matrix.msc4143.rtc_foci
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_connect_timeout 3s;
        proxy_send_timeout 15m;
        proxy_read_timeout 15m;
      '';
    };
    locations."~ ^/_matrix/" = {
      proxyPass = "http://127.0.0.1:8088";
      proxyWebsockets = true;
      extraConfig = "proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto https; proxy_connect_timeout 3s; proxy_send_timeout 15m; proxy_read_timeout 15m;";
    };
    locations."/livekit/jwt/" = {
      proxyPass = "http://127.0.0.1:8090/";
      extraConfig = "proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto https; proxy_http_version 1.1; proxy_set_header Connection \"\";";
    };
    # ponytail: serve here too so in-browser clients (Cinny) doing discovery on the
    # homeserver host don't fall through the SPA catch-all to index.html (200 HTML)
    # and abort with 'configuration appears unusable'. Same-origin, no CORS needed.
    locations."/.well-known/matrix/client" = {
      extraConfig = ''add_header Content-Type application/json; return 200 '${lib.toJSON clientConfig}';'';
    };
  };

  services.nginx.virtualHosts."marcel.cool" = {
    forceSSL = true;
    useACMEHost = "marcel.cool";
    locations."/" = {
      extraConfig = "return 301 https://followthetrace.com$request_uri;";
    };
    locations."/.well-known/matrix/client" = {
      extraConfig = ''add_header Content-Type application/json; return 200 '${lib.toJSON clientConfig}';'';
    };
    locations."/.well-known/matrix/server" = {
      extraConfig = "add_header Content-Type application/json; return 200 '{\"m.server\": \"marcel.cool:443\"}';";
    };
    locations."~ ^/_matrix/" = {
      proxyPass = "http://127.0.0.1:8088";
      proxyWebsockets = true;
      extraConfig = "proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto https; proxy_connect_timeout 3s; proxy_send_timeout 15m; proxy_read_timeout 15m;";
    };
  };

  services.nginx.virtualHosts."www.marcel.cool" = {
    forceSSL = true;
    useACMEHost = "marcel.cool";
    locations."/" = {
      extraConfig = "return 301 https://blog.marcel.cool$request_uri;";
    };
  };

  services.coturn = {
    enable = true;
    listening-ips = ["0.0.0.0" "::"];
    listening-port = 3478;
    min-port = 49152;
    max-port = 49200;
    static-auth-secret = config.sops.placeholder.coturn_secret;
  };

  services.lk-jwt-service = {
    enable = true;
    livekitUrl = "wss://livekit.marcel.cool";
    keyFile = config.sops.templates."livekit-secrets".path;
    port = 8090;
  };

  services.matrix-synapse.settings.turn_servers = [{
    urls = ["turn:${domain}:3478" "turn:${domain}:3478?transport=udp"];
    username = "turn_user";
    credential = config.sops.placeholder.coturn_secret;
  }];

  networking.firewall.allowedTCPPorts = [80 443 3478];
  networking.firewall.allowedUDPPorts = [3478];
  networking.firewall.allowedUDPPortRanges = [{ from = 49152; to = 49200; }];
}
