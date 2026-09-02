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
    azuracast = {
      port = 8280;
      href = "https://radio.marcel.cool";
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
      protected = true;
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
    nitter = {
      port = 8087;
      href = "https://nitter.marcel.cool";
      protected = true;
    };
    offtiktok = {
      port = 3010;
      href = "https://offtiktok.marcel.cool";
    };
    offtiktokapi = {
      port = 2000;
      href = "https://api.offtiktok.marcel.cool";
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
      # Arr stack talks to qbit on localhost, so this only gates browser access.
      protected = true;
    };
    radarr = {
      port = 7878;
      href = "https://radarr.marcel.cool";
    };
    pinchflat = {
      port = 8945;
      href = "https://pinchflat.marcel.cool";
      protected = true;
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
      # host-side published ports for the 13.0 sibling containers (host nginx
      # reaches these; container-internal ports are 8083 for notification, 80 for seadoc)
      notifPort = 8009;
      seadocPort = 8888;
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
    syncthing = {
      port = 8384;
      href = "https://sync.marcel.cool";
      protected = true;
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
    youtube = {
      port = 9800;
      href = "https://yt.marcel.cool";
      protected = true;
    };
    vaultwarden = {
      port = 8222;
      href = "https://vault.marcel.cool";
    };
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
        # only redirect top-level browser navigations to the maintenance page.
        if ($http_sec_fetch_mode = navigate) {
          rewrite ^ https://maintenance.marcel.cool?from=${lib.removePrefix "https://" service.href} redirect;
        }
        return 503;
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
          return 302 https://auth.marcel.cool/?rd=$scheme://$http_host$request_uri&rm=$request_method;
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
      domain = "marcel.cool";
      extraDomainNames = ["*.marcel.cool"];
      dnsProvider = "cloudflare";
      environmentFile = config.sops.templates."cloudflare-acme.env".path;
      dnsPropagationCheck = true;
    };
    certs."matrix.marcel.cool" = {
      domain = "*.matrix.marcel.cool";
      dnsProvider = "cloudflare";
      environmentFile = config.sops.templates."cloudflare-acme.env".path;
      dnsPropagationCheck = true;
    };
  };

  services.nginx = {
    enable = true;
    clientMaxBodySize = "0";

    virtualHosts =
      (builtins.removeAttrs serviceVirtualHosts ["auth" "jellyfin" "seafile" "azuracast"])
      // {
        "jellyfin.marcel.cool" = let
          base = mkProxyHost "jellyfin" services.jellyfin;
        in
          base
          // {
            locations =
              base.locations
              // {
                "/web/" = {
                  proxyPass = "http://127.0.0.1:${toString services.jellyfin.port}";
                  proxyWebsockets = true;
                  extraConfig = ''
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto https;
                    proxy_set_header X-Forwarded-Host $host;
                    proxy_hide_header Cache-Control;
                    add_header Cache-Control "no-cache" always;
                    error_page 502 503 504 = @maintenance;
                  '';
                };
              };
          };

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

        "seafile.marcel.cool" = let
          base = mkProxyHost "seafile" services.seafile;
        in
          base
          // {
            locations =
              base.locations
              // {
                # WebDAV is disabled (seafdav.conf enabled=false, no wsgidav on :8080).
                "/seafdav".return = "404";
                # notification-server (separate container in 13.0); strip /notification prefix
                "/notification" = {
                  proxyPass = "http://127.0.0.1:${toString services.seafile.notifPort}";
                  proxyWebsockets = true;
                  extraConfig = ''
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto https;
                  '';
                };
                # SeaDoc (separate container); strip /sdoc-server prefix
                "/sdoc-server/" = {
                  proxyPass = "http://127.0.0.1:${toString services.seafile.seadocPort}/";
                  proxyWebsockets = true;
                  extraConfig = ''
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto https;
                    proxy_set_header X-Forwarded-Host $server_name;
                    client_max_body_size 100m;
                  '';
                };
                # SeaDoc websocket; keep /socket.io prefix
                "/socket.io" = {
                  proxyPass = "http://127.0.0.1:${toString services.seafile.seadocPort}";
                  proxyWebsockets = true;
                  extraConfig = ''
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto https;
                    proxy_buffers 8 32k;
                    proxy_buffer_size 64k;
                  '';
                };
              };
          };

        # azuracast public face, admin/login routes bounce to the studio host
        "radio.marcel.cool" = let
          base = mkProxyHost "azuracast" services.azuracast;
        in
          base
          // {
            # AzuraCast sends `Permissions-Policy: autoplay=*, fullscreen=*, interest-cohort=()`.
            # interest-cohort is the dead FLoC token; Brave logs it as an unrecognized
            # directive. Drop the upstream header and re-issue a clean one without it.
            extraConfig =
              base.extraConfig
              + ''
                proxy_hide_header Permissions-Policy;
                add_header Permissions-Policy "autoplay=*, fullscreen=*" always;
              '';
            locations =
              base.locations
              // {
                # serve the public page at the clean root — internal rewrite,
                "= /" = {
                  extraConfig = "rewrite ^ /public/radio_marcel?hide_history=1&hide_playlist=1 last;";
                };
                "/admin" = {
                  return = "302 https://studio.marcel.cool$request_uri";
                };
                "/login" = {
                  return = "302 https://studio.marcel.cool$request_uri";
                };
                "/logout" = {
                  return = "302 https://studio.marcel.cool$request_uri";
                };
                "= /stream" = {
                  proxyPass = "http://127.0.0.1:${toString services.azuracast.port}/listen/radio_marcel/radio.mp3";
                  extraConfig = ''
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto https;
                    proxy_buffering off;
                    proxy_request_buffering off;
                    proxy_read_timeout 1h;
                    proxy_send_timeout 1h;
                  '';
                };
                # lossless twin of /stream; 404s until the FLAC mount /radio.flac exists
                # (inserted declaratively by azuracast/default.nix, like the HLS rows).
                "= /lossless-stream" = {
                  proxyPass = "http://127.0.0.1:${toString services.azuracast.port}/listen/radio_marcel/radio.flac";
                  extraConfig = ''
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto https;
                    proxy_buffering off;
                    proxy_request_buffering off;
                    proxy_read_timeout 1h;
                    proxy_send_timeout 1h;
                  '';
                };
                # The player itself requests /listen/<station>/radio.mp3 directly (not via
                # /stream above), which otherwise falls through to base "/" - no
                # proxy_buffering off there, so nginx tries to buffer this endless stream
                # instead of flushing it straight through. Same bug class /stream and /live/
                # were already fixed for, just missed on the path actually in use; likely
                # cause of the audio randomly stalling (?azdebug: net::ERR_NETWORK_CHANGED /
                # waiting / stalled, recurring across fresh browser contexts).
                "/listen/" = {
                  proxyPass = "http://127.0.0.1:${toString services.azuracast.port}";
                  extraConfig = ''
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto https;
                    proxy_buffering off;
                    proxy_request_buffering off;
                    proxy_read_timeout 1h;
                    proxy_send_timeout 1h;
                  '';
                };
                # Centrifugo-backed SSE (now-playing live updates). Base "/" location has no
                # proxy_buffering off, so nginx buffers the event stream instead of flushing it
                # -> updates arrive up to ~15s late / look dead. SSE needs the same no-buffering
                # treatment as /stream.
                "/live/" = {
                  proxyPass = "http://127.0.0.1:${toString services.azuracast.port}";
                  proxyWebsockets = true; # Centrifugo can fall back to a websocket transport under this prefix
                  extraConfig = ''
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto https;
                    proxy_buffering off;
                    proxy_cache off;
                    proxy_read_timeout 1h;
                    proxy_send_timeout 1h;
                  '';
                };
                # Declarative default background for the public page (azuracast/public/)
                # - served directly by nginx from the repo-tracked file below, not AzuraCast's
                # own asset uploader (that names files with an opaque hash under
                # /static/uploads/, so it isn't reproducible/declarative across fresh installs).
                "= /party-bg.jpg" = {
                  alias = "${./azuracast/public/background.jpg}";
                  extraConfig = ''
                    add_header Cache-Control "public, max-age=31536000, immutable";
                  '';
                };
                # Per-IP listen-time counter for the public page. Proxied to the
                # azuracast-listen-time service (azuracast.nix) on loopback; exact match so the
                # base "/" location above doesn't swallow it. Port must match listenTimePort there.
                "= /listen-time" = {
                  proxyPass = "http://127.0.0.1:8320";
                  extraConfig = ''
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto https;
                    proxy_connect_timeout 3s;
                    proxy_read_timeout 10s;
                  '';
                };
              };
          };
        "studio.marcel.cool" = let
          base = mkProxyHost "studio" {
            port = services.azuracast.port;
            href = "https://studio.marcel.cool";
          };
        in
          base
          // {
            locations =
              base.locations
              // {
                "= /" = {
                  return = "302 /admin";
                };
              };
          };

        "brave-origin-channels.marcel.cool" = {
          forceSSL = true;
          useACMEHost = "marcel.cool";
          root = "/var/lib/brave-origin-channels";
          locations."/" = {
            index = "index.html";
            tryFiles = "$uri $uri/ =404";
          };
          locations."/_webhook/" = {
            proxyPass = "http://127.0.0.1:9000";
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            '';
          };
        };

        # Catch-all static host for *.marcel.cool subdomains not listed above.
        # Serves /var/www/pages/<sub>/index.html — used by `pir report --page`
        # (and anything else that drops a self-contained HTML file there).
        # Regex server_name is lowest priority, so explicit vhosts above win.
        "~^(?<sub>[^.]+)\\.marcel\\.cool$" = {
          forceSSL = true;
          useACMEHost = "marcel.cool";
          root = "/var/www/pages/$sub";
          locations."/" = {
            index = "index.html";
            tryFiles = "$uri $uri/ =404";
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

  # /var/www/pages is the docroot for the catch-all *.marcel.cool vhost above.
  # Owned by dev (who runs `pir report` on this host); 0755 so nginx can traverse+read.
  systemd.tmpfiles.rules = [
    "d /var/www/pages 0755 dev users -"
  ];

  users.users.nginx.extraGroups = ["acme"];
}
