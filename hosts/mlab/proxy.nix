{
  config,
  _pkgs,
  lib,
  ...
}: let
  services = {
    attic = {
      port = 4321;
      href = "https://cache.marcel.cool";
    };
    audiobooks = {
      port = 8000;
      href = "https://audiobooks.marcel.cool";
    };
    auth = {
      port = 9091;
      href = "https://auth.marcel.cool";
    };
    bazarr = {
      port = 6767;
      href = "https://bazarr.marcel.cool";
    };
    calibre = {
      port = 8083;
      href = "https://calibre.marcel.cool";
    };
    chaptarr = {
      port = 8789;
      href = "https://chaptarr.marcel.cool";
    };
    grafana = {
      port = 3005;
      href = "https://grafana.marcel.cool";
    };
    home = {
      port = 8082;
      href = "https://home.marcel.cool";
    };
    immich = {
      port = 2283;
      href = "https://img.marcel.cool";
    };
    jellyfin = {
      port = 8096;
      href = "https://jellyfin.marcel.cool";
    };
    lidarr = {
      port = 8686;
      href = "https://lidarr.marcel.cool";
    };
    miniflux = {
      port = 8085;
      href = "https://rss.marcel.cool";
    };
    navidrome = {
      port = 4533;
      href = "https://music.marcel.cool";
    };
    openwebui = {
      port = 3000;
      href = "https://ai.marcel.cool";
    };
    prowlarr = {
      port = 9696;
      href = "https://prowlarr.marcel.cool";
    };
    qbit = {
      port = 8081;
      href = "https://qbit.marcel.cool";
    };
    radarr = {
      port = 7878;
      href = "https://radarr.marcel.cool";
    };
    paperless = {
      port = 28981;
      href = "https://paperless.marcel.cool";
    };
    sabnzbd = {
      port = 8080;
      href = "https://sabnzbd.marcel.cool";
    };
    seafile = {
      port = 8008;
      href = "https://seafile.marcel.cool";
    };
    seerr = {
      port = 5055;
      href = "https://seerr.marcel.cool";
    };
    shoko = {
      port = 8111;
      href = "https://shoko.marcel.cool";
    };
    slskd = {
      port = 5030;
      href = "https://slskd.marcel.cool";
    };
    sonarr = {
      port = 8989;
      href = "https://sonarr.marcel.cool";
    };
    soulbeet = {
      port = 9765;
      href = "https://soulbeet.marcel.cool";
    };
    status = {
      port = 3001;
      href = "https://status.marcel.cool";
    };
    prometheus = {
      port = 9090;
      href = "http://127.0.0.1:9090";
    };
    searxng = {
      port = 8084;
      href = "https://search.marcel.cool";
      protected = true;
    };
    stalwart = {
      port = 8086;
      href = "https://jmap.marcel.cool";
    };
    youtube = {
      port = 9800;
      href = "https://yt.marcel.cool";
    };
    stalwartadmin = {
      port = 8087;
      href = "https://jmap-admin.marcel.cool";
      protected = true;
    };
    # ytmusic = {
    #   port = 9801;
    #   href = "https://ytmusic.marcel.cool";
    #   protected = true;
    # };
    # pipedapi = {
    #   port = 9802;
    #   href = "https://pipedapi.marcel.cool";
    # };
    # pipedproxy = {
    #   port = 9803;
    #   href = "https://pipedproxy.marcel.cool";
    # };
  };

  mkProxyHost = name: service: {
    serverName = lib.removePrefix "https://" service.href;
    forceSSL = true;
    useACMEHost = "marcel.cool";

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString service.port}";
      proxyWebsockets = true;
      extraConfig = ''
        # Tell the app what the original URL and IP were
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;

        proxy_connect_timeout 3s;
        proxy_send_timeout 15m;
        proxy_read_timeout 15m;
        error_page 502 503 504 = @maintenance;

        ${lib.optionalString (service.protected or false) ''
          auth_request /internal/authelia/authz;
          error_page 401 = @authelia_login;
        ''}
      '';
    };
    extraConfig = ''
      location @maintenance {
        return 307 https://maintenance.marcel.cool?from=${lib.removePrefix "https://" service.href};
      }

      ${lib.optionalString (service.protected or false) ''
        location /internal/authelia/authz {
          internal;
          proxy_pass http://127.0.0.1:${toString services.auth.port}/api/verify;
          proxy_pass_request_body off;
          proxy_set_header Content-Length "";
          proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
          proxy_set_header X-Forwarded-Method $request_method;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Host $http_host;
          proxy_set_header X-Forwarded-URI $request_uri;
          proxy_set_header X-Forwarded-For $remote_addr;
        }

        location @authelia_login {
          return 302 https://auth.marcel.cool/?rm=$request_method;
        }
      ''}
    '';
  };

  serviceVirtualHosts = lib.mapAttrs mkProxyHost services;
in {
  _module.args.services = services;

  security.acme = {
    acceptTerms = true;
    defaults.email = "admin@marcel.cool";
    certs."marcel.cool" = {
      domain = "*.marcel.cool";
      dnsProvider = "cloudflare";
      environmentFile = config.sops.templates."cloudflare-acme.env".path;
      dnsPropagationCheck = true;
    };
  };

  services.nginx = {
    enable = true;
    clientMaxBodySize = "0";

    virtualHosts =
      (builtins.removeAttrs serviceVirtualHosts ["auth.marcel.cool"])
      // {
        "auth.marcel.cool" = let
          base = mkProxyHost "auth" services.auth;
        in
          base
          // {
            locations =
              base.locations
              // {
                "/.well-known/webfinger".extraConfig = ''
                  add_header Content-Type application/jrd+json;
                  return 200 '{"subject":"acct:authelia@auth.marcel.cool","links":[{"rel":"http://openid.net/specs/connect/1.0/issuer","href":"https://auth.marcel.cool"}]}';
                '';
              };
          };

        "_" = {
          default = true;
          listen = [
            {
              addr = "0.0.0.0";
              port = 80;
            }
          ];
          locations."/" = {
            return = "307 https://maintenance.marcel.cool";
          };
        };
      };
  };

  users.users.nginx.extraGroups = ["acme"];
}
