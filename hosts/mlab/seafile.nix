{
  config,
  pkgs,
  services,
  ...
}: let
  domain = "seafile.marcel.cool";
in {
  sops = {
    secrets = {
      "seafile_admin_pass" = {};
      "seafile_db_pass" = {};
      "seafile_jwt_key" = {};
    };

    templates = {
      "seafile-db.env".content = ''
        MYSQL_ROOT_PASSWORD=${config.sops.placeholder.app_pass}
        MYSQL_LOG_CONSOLE=true
        MARIADB_AUTO_UPGRADE=1
      '';

      "seafile-app.env".content = ''
        SEAFILE_MYSQL_DB_HOST=seafile-db
        SEAFILE_MYSQL_DB_PORT=3306
        SEAFILE_MYSQL_DB_USER=seafile
        SEAFILE_MYSQL_DB_PASSWORD=${config.sops.placeholder.seafile_db_pass}
        INIT_SEAFILE_MYSQL_ROOT_PASSWORD=${config.sops.placeholder.app_pass}
        SEAFILE_MYSQL_DB_CCNET_DB_NAME=ccnet_db
        SEAFILE_MYSQL_DB_SEAFILE_DB_NAME=seafile_db
        SEAFILE_MYSQL_DB_SEAHUB_DB_NAME=seahub_db
        TIME_ZONE=${config.time.timeZone}
        INIT_SEAFILE_ADMIN_EMAIL=admin@marcel.cool
        INIT_SEAFILE_ADMIN_PASSWORD=${config.sops.placeholder.seafile_admin_pass}
        JWT_PRIVATE_KEY=${config.sops.placeholder.seafile_jwt_key}
        CACHE_PROVIDER=redis
        REDIS_HOST=seafile-redis
        REDIS_PORT=6379
        ENABLE_NOTIFICATION_SERVER=true
        INNER_NOTIFICATION_SERVER_URL=http://seafile-notification:8083
        NOTIFICATION_SERVER_URL=https://${domain}/notification
        ENABLE_SEADOC=true
        SEADOC_SERVER_URL=https://${domain}/sdoc-server
        SEAFILE_LOG_TO_STDOUT=false
      '';

      "seafile-notification.env".content = ''
        SEAFILE_MYSQL_DB_HOST=seafile-db
        SEAFILE_MYSQL_DB_PORT=3306
        SEAFILE_MYSQL_DB_USER=seafile
        SEAFILE_MYSQL_DB_PASSWORD=${config.sops.placeholder.seafile_db_pass}
        SEAFILE_MYSQL_DB_CCNET_DB_NAME=ccnet_db
        SEAFILE_MYSQL_DB_SEAFILE_DB_NAME=seafile_db
        JWT_PRIVATE_KEY=${config.sops.placeholder.seafile_jwt_key}
        SEAFILE_LOG_TO_STDOUT=false
        NOTIFICATION_SERVER_LOG_LEVEL=info
      '';

      "seafile-seadoc.env".content = ''
        DB_HOST=seafile-db
        DB_PORT=3306
        DB_USER=seafile
        DB_PASSWORD=${config.sops.placeholder.seafile_db_pass}
        DB_NAME=seahub_db
        TIME_ZONE=${config.time.timeZone}
        JWT_PRIVATE_KEY=${config.sops.placeholder.seafile_jwt_key}
        SEAHUB_SERVICE_URL=http://seafile-app
      '';
    };
  };

  systemd = {
    tmpfiles.rules = [
      "d /var/lib/seafile 0755 root root -"
      "d /var/lib/seafile/db 0755 root root -"
      "d /var/lib/seafile/data 0755 root root -"
      "d /var/lib/seadoc 0755 root root -"
    ];

    services = {
      podman-network-seafile = {
        description = "Create Podman network for Seafile";
        after = [
          "network.target"
          "podman.service"
          "podman.socket"
        ];
        requires = [
          "podman.service"
          "podman.socket"
        ];
        path = [
          pkgs.gnused
          pkgs.coreutils
          pkgs.gnugrep
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.podman}/bin/podman network inspect seafile-net >/dev/null 2>&1 || ${pkgs.podman}/bin/podman network create seafile-net'";
        };
        wantedBy = ["multi-user.target"];
      };

      "podman-seafile-db".after = ["podman-network-seafile.service"];
      "podman-seafile-db".requires = ["podman-network-seafile.service"];
      "podman-seafile-redis".after = ["podman-network-seafile.service"];
      "podman-seafile-redis".requires = ["podman-network-seafile.service"];
      "podman-seafile-notification".after = ["podman-network-seafile.service"];
      "podman-seafile-notification".requires = ["podman-network-seafile.service"];
      "podman-seafile-seadoc".after = ["podman-network-seafile.service"];
      "podman-seafile-seadoc".requires = ["podman-network-seafile.service"];

      "podman-seafile-app" = {
        after = ["podman-network-seafile.service"];
        requires = ["podman-network-seafile.service"];
        preStart = ''
          CONF_DIR="/var/lib/seafile/data/seafile/conf"
          mkdir -p "$CONF_DIR"
          SETTINGS="$CONF_DIR/seahub_settings.py"
          touch "$SETTINGS"
          # 13.0 derives SERVICE_URL / FILE_SERVER_ROOT / DATABASES / CACHES from env
          # (settings.py overrides anything in this file). CSRF is still file-based.
          if ! grep -q "CSRF_TRUSTED_ORIGINS" "$SETTINGS"; then
            echo "CSRF_TRUSTED_ORIGINS = ['https://${domain}']" >> "$SETTINGS"
          fi
          if ! grep -q "THUMBNAIL_SIZE_FOR_ORIGINAL" "$SETTINGS"; then
            echo "THUMBNAIL_SIZE_FOR_ORIGINAL = 4096" >> "$SETTINGS"
          fi
        '';
      };
    };
  };

  virtualisation.oci-containers.containers = {
    seafile-db = {
      image = "docker.io/library/mariadb:10.11";
      volumes = ["/var/lib/seafile/db:/var/lib/mysql"];
      environmentFiles = [config.sops.templates."seafile-db.env".path];
      extraOptions = ["--network=seafile-net"];
    };

    seafile-redis = {
      image = "docker.io/library/redis:7";
      cmd = ["redis-server" "--save" "" "--appendonly" "no"];
      extraOptions = ["--network=seafile-net"];
    };

    seafile-notification = {
      image = "docker.io/seafileltd/notification-server:13.0-latest";
      volumes = ["/var/lib/seafile/data/seafile/logs:/shared/seafile/logs"];
      environmentFiles = [config.sops.templates."seafile-notification.env".path];
      ports = ["127.0.0.1:${toString services.seafile.notifPort}:8083"];
      extraOptions = ["--network=seafile-net"];
      dependsOn = ["seafile-db"];
    };

    seafile-seadoc = {
      image = "docker.io/seafileltd/sdoc-server:2.0-latest";
      volumes = ["/var/lib/seadoc:/shared"];
      environmentFiles = [config.sops.templates."seafile-seadoc.env".path];
      ports = ["127.0.0.1:${toString services.seafile.seadocPort}:80"];
      extraOptions = ["--network=seafile-net"];
      dependsOn = ["seafile-db"];
    };

    seafile-app = {
      image = "docker.io/seafileltd/seafile-mc:13.0.25";
      volumes = ["/var/lib/seafile/data:/shared"];
      environmentFiles = [config.sops.templates."seafile-app.env".path];
      environment = {
        SEAFILE_SERVER_HOSTNAME = "${domain}";
        SEAFILE_SERVER_PROTOCOL = "https";
        ENABLE_GO_FILESERVER = "true";
      };
      ports = ["127.0.0.1:${toString services.seafile.port}:80"];
      extraOptions = ["--network=seafile-net"];
      dependsOn = [
        "seafile-db"
        "seafile-redis"
      ];
    };
  };
}
