{
  config,
  services,
  ...
}: {
  sops.templates."homepage.env" = {
    content = ''
      HOMEPAGE_ALLOWED_HOSTS="home.marcel.cool,127.0.0.1,localhost"
      HOMEPAGE_VAR_WEB_USER='${config.sops.placeholder.web_user}'
      HOMEPAGE_VAR_WEB_PASS='${config.sops.placeholder.web_pass}'
      HOMEPAGE_VAR_SONARR_API='${config.sops.placeholder.sonarr_api}'
      HOMEPAGE_VAR_RADARR_API='${config.sops.placeholder.radarr_api}'
      HOMEPAGE_VAR_LIDARR_API='${config.sops.placeholder.lidarr_api}'
      HOMEPAGE_VAR_PROWLARR_API='${config.sops.placeholder.prowlarr_api}'
      HOMEPAGE_VAR_SABNZBD_API='${config.sops.placeholder.sabnzbd_api}'
      HOMEPAGE_VAR_JELLYFIN_API='${config.sops.placeholder.jellyfin_api}'
      HOMEPAGE_VAR_NAVIDROME_TOKEN='${config.sops.placeholder.navidrome_token}'
      HOMEPAGE_VAR_NAVIDROME_SALT='${config.sops.placeholder.navidrome_salt}'
      HOMEPAGE_VAR_BAZARR_API='${config.sops.placeholder.bazarr_api}'
      HOMEPAGE_VAR_IMMICH_API='${config.sops.placeholder.immich_api}'
      HOMEPAGE_VAR_SEERR_API='${config.sops.placeholder.seerr_api}'
      HOMEPAGE_VAR_PAPERLESS_API='${config.sops.placeholder.paperless_api}'
      HOMEPAGE_VAR_MINIFLUX_API='${config.sops.placeholder.miniflux_api}'
    '';
  };
  services.homepage-dashboard = {
    enable = true;
    listenPort = services.home.port;
    environmentFiles = [config.sops.templates."homepage.env".path];

    settings = {
      title = "Mlab Dashboard";
      color = "zinc";
      theme = "dark";
      useEqualHeights = true;
      layout = {
        "Media" = {
          style = "row";
          columns = 4;
        };
        "Automation" = {
          style = "row";
          columns = 4;
        };
        "Downloads" = {
          style = "row";
          columns = 3;
        };
        "Infrastructure" = {
          style = "row";
          columns = 3;
        };
      };
    };

    widgets = [
      {
        search = {
          provider = "custom";
          url = "https://search.marcel.cool/search?q=";
          target = "_blank";
        };
      }
      {
        resources = {
          cpu = true;
          memory = true;
          disk = "/";
        };
      }
    ];

    services = [
      {
        "Media" = [
          {
            Jellyfin = {
              icon = "jellyfin";
              href = services.jellyfin.href;
              description = "Movies & TV";
              # widget = {
              #   type = "jellyfin";
              #   url = "http://127.0.0.1:${toString services.jellyfin.port}";
              #   key = "{{HOMEPAGE_VAR_JELLYFIN_API}}";
              # };
            };
          }
          {
            Navidrome = {
              icon = "navidrome";
              href = services.navidrome.href;
              description = "Music Streamer";
              widget = {
                type = "navidrome";
                url = "http://127.0.0.1:${toString services.navidrome.port}";
                user = "{{HOMEPAGE_VAR_WEB_USER}}";
                salt = "{{HOMEPAGE_VAR_NAVIDROME_SALT}}";
                token = "{{HOMEPAGE_VAR_NAVIDROME_TOKEN}}";
              };
            };
          }
          {
            Immich = {
              icon = "immich";
              href = services.immich.href;
              description = "Photos";
              widget = {
                type = "immich";
                url = "http://127.0.0.1:${toString services.immich.port}";
                key = "{{HOMEPAGE_VAR_IMMICH_API}}";
                version = 2;
              };
            };
          }
          {
            Audiobookshelf = {
              icon = "audiobookshelf";
              href = services.audiobooks.href;
              description = "Audiobooks";
            };
          }
          {
            Calibre = {
              icon = "calibre";
              href = services.calibre.href;
              description = "E-Book Library";
            };
          }
        ];
      }
      {
        "Automation" = [
          {
            Seerr = {
              icon = "seerr";
              href = services.seerr.href;
              description = "Requests";
              widget = {
                type = "seerr";
                url = "http://127.0.0.1:${toString services.seerr.port}";
                key = "{{HOMEPAGE_VAR_SEERR_API}}";
              };
            };
          }
          {
            Sonarr = {
              icon = "sonarr";
              href = services.sonarr.href;
              widget = {
                type = "sonarr";
                url = "http://127.0.0.1:${toString services.sonarr.port}";
                key = "{{HOMEPAGE_VAR_SONARR_API}}";
              };
            };
          }
          {
            Radarr = {
              icon = "radarr";
              href = services.radarr.href;
              widget = {
                type = "radarr";
                url = "http://127.0.0.1:${toString services.radarr.port}";
                key = "{{HOMEPAGE_VAR_RADARR_API}}";
              };
            };
          }
          {
            Lidarr = {
              icon = "lidarr";
              href = services.lidarr.href;
              widget = {
                type = "lidarr";
                url = "http://127.0.0.1:${toString services.lidarr.port}";
                key = "{{HOMEPAGE_VAR_LIDARR_API}}";
              };
            };
          }
          {
            Bazarr = {
              icon = "bazarr";
              href = services.bazarr.href;
              widget = {
                type = "bazarr";
                url = "http://127.0.0.1:${toString services.bazarr.port}";
                key = "{{HOMEPAGE_VAR_BAZARR_API}}";
              };
            };
          }
          {
            Prowlarr = {
              icon = "prowlarr";
              href = services.prowlarr.href;
              widget = {
                type = "prowlarr";
                url = "http://127.0.0.1:${toString services.prowlarr.port}";
                key = "{{HOMEPAGE_VAR_PROWLARR_API}}";
              };
            };
          }
          {
            Chaptarr = {
              icon = "readarr";
              href = services.chaptarr.href;
              description = "Audiobook Automation";
            };
          }
          {
            Soulbeet = {
              icon = "music";
              href = services.soulbeet.href;
              description = "Music Tagging";
            };
          }
        ];
      }
      {
        "Downloads" = [
          {
            qBittorrent = {
              icon = "qbittorrent";
              href = services.qbit.href;
              widget = {
                type = "qbittorrent";
                url = "http://127.0.0.1:${toString services.qbit.port}";
                username = "{{HOMEPAGE_VAR_WEB_USER}}";
                password = "{{HOMEPAGE_VAR_WEB_PASS}}";
              };
            };
          }
          {
            SABnzbd = {
              icon = "sabnzbd";
              href = services.sabnzbd.href;
              widget = {
                type = "sabnzbd";
                url = "http://127.0.0.1:${toString services.sabnzbd.port}";
                key = "{{HOMEPAGE_VAR_SABNZBD_API}}";
              };
            };
          }
          {
            Slskd = {
              icon = "soulseek";
              href = services.slskd.href;
              description = "P2P Music";
            };
          }
        ];
      }
      {
        "Infrastructure" = [
          {
            "Open WebUI" = {
              icon = "ollama";
              href = services.openwebui.href;
              description = "Local AI";
            };
          }
          {
            Seafile = {
              icon = "seafile";
              href = services.seafile.href;
              description = "File Sync";
            };
          }
          {
            Paperless = {
              icon = "paperless-ngx";
              href = services.paperless.href;
              description = "Document Management";
              widget = {
                type = "paperlessngx";
                url = "http://127.0.0.1:${toString services.paperless.port}";
                key = "{{HOMEPAGE_VAR_PAPERLESS_API}}";
              };
            };
          }
          {
            Status = {
              icon = "uptime-kuma";
              href = "${services.status.href}/status/mlab";
              description = "Uptime Kuma";
              widget = {
                type = "uptimekuma";
                url = "http://127.0.0.1:${toString services.status.port}";
                slug = "mlab";
              };
            };
          }
          {
            Grafana = {
              icon = "grafana";
              href = services.grafana.href;
              description = "Server Metrics";
            };
          }
          {
            Invidious = {
              icon = "invidious";
              href = services.youtube.href;
              description = "Invidious Tube";
            };
          }
          {
            Miniflux = {
              icon = "miniflux";
              href = services.miniflux.href;
              description = "Feed server and reader";
              widget = {
                type = "miniflux";
                url = "http://127.0.0.1:${toString services.miniflux.port}";
                key = "{{HOMEPAGE_VAR_MINIFLUX_API}}";
              };
            };
          }
        ];
      }
    ];
  };
}
