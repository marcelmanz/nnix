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
    };

    templates = {
      "seafile-db.env".content = ''
        MYSQL_ROOT_PASSWORD=${config.sops.placeholder.app_pass}
        MYSQL_LOG_CONSOLE=true
      '';

      "seafile-app.env".content = ''
        DB_HOST=seafile-db
        DB_ROOT_PASSWD=${config.sops.placeholder.app_pass}
        TIME_ZONE=${config.time.timeZone}
        SEAFILE_ADMIN_EMAIL=admin@marcel.cool
        SEAFILE_ADMIN_PASSWORD=${config.sops.placeholder.seafile_admin_pass}
        SEAFILE_SERVER_LETSENCRYPT=false
        SEAFILE_MEMCACHED_HOST=seafile-memcached
        SEAFILE_MEMCACHED_PORT=11211
      '';
    };
  };

  systemd = {
    tmpfiles.rules = [
      "d /var/lib/seafile 0755 root root -"
      "d /var/lib/seafile/db 0755 root root -"
      "d /var/lib/seafile/data 0755 root root -"
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
      "podman-seafile-memcached".after = ["podman-network-seafile.service"];
      "podman-seafile-memcached".requires = ["podman-network-seafile.service"];

      "podman-seafile-app" = {
        after = ["podman-network-seafile.service"];
        requires = ["podman-network-seafile.service"];
        preStart = ''
          CONF_DIR="/var/lib/seafile/data/seafile/conf"
          mkdir -p "$CONF_DIR"
          SETTINGS="$CONF_DIR/seahub_settings.py"
          touch "$SETTINGS"
          if ! grep -q "CSRF_TRUSTED_ORIGINS" "$SETTINGS"; then
            echo "CSRF_TRUSTED_ORIGINS = ['https://${domain}']" >> "$SETTINGS"
          fi
          CCNET="$CONF_DIR/ccnet.conf"
          if [ -f "$CCNET" ]; then
            sed -i 's|http://${domain}|https://${domain}|g' "$CCNET"
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

    seafile-memcached = {
      image = "docker.io/library/memcached:1.6";
      cmd = [
        "memcached"
        "-m"
        "256"
      ];
      extraOptions = ["--network=seafile-net"];
    };

    seafile-app = {
      image = "docker.io/seafileltd/seafile-mc:latest";
      volumes = ["/var/lib/seafile/data:/shared"];
      environmentFiles = [config.sops.templates."seafile-app.env".path];
      environment = {
        SEAFILE_SERVER_HOSTNAME = "${domain}";
        SEAFILE_SERVER_PROTOCOL = "https";
      };
      ports = ["127.0.0.1:${toString services.seafile.port}:80"];
      extraOptions = ["--network=seafile-net"];
      dependsOn = [
        "seafile-db"
        "seafile-memcached"
      ];
    };
  };
}
