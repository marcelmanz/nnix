{
  config,
  pkgs,
  lib,
  services,
  ...
}: {
  sops.secrets.piped_db_password = {
    owner = "postgres";
  };

  sops.templates."piped-config.properties" = {
    content = ''
      PORT:${toString services.pipedapi.port}
      HTTP_WORKERS:2
      PROXY_PART:${services.pipedproxy.href}
      API_URL:${services.pipedapi.href}
      FRONTEND_URL:${services.ytmusic.href}
      COMPROMISED_PASSWORD_CHECK:true
      DISABLE_REGISTRATION:false
      FEED_RETENTION:30
      hibernate.connection.url:jdbc:postgresql://127.0.0.1:5432/piped
      hibernate.connection.driver_class:org.postgresql.Driver
      hibernate.dialect:org.hibernate.dialect.PostgreSQLDialect
      hibernate.connection.username:piped
      hibernate.connection.password:${config.sops.placeholder.piped_db_password}
    '';
  };

  services.postgresql = {
    ensureDatabases = ["piped"];
    ensureUsers = [
      {
        name = "piped";
        ensureDBOwnership = true;
      }
    ];
  };

  systemd.services.piped-db-password = {
    description = "Set piped postgres password from sops";
    after = ["postgresql.service"];
    requires = ["postgresql.service"];
    before = ["podman-piped-backend.service"];
    wantedBy = [
      "multi-user.target"
      "podman-piped-backend.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
    };
    script = ''
      pw=$(cat ${config.sops.secrets.piped_db_password.path})
      ${config.services.postgresql.package}/bin/psql -c "ALTER USER piped WITH PASSWORD '$pw';"
    '';
  };

  virtualisation.oci-containers.containers = {
    piped-backend = {
      image = "1337kavin/piped:latest";
      volumes = [
        "${config.sops.templates."piped-config.properties".path}:/app/config.properties:ro"
      ];
      extraOptions = ["--network=host"];
    };

    piped-proxy = {
      image = "1337kavin/piped-proxy:latest";
      environment = {
        BIND = "127.0.0.1:${toString services.pipedproxy.port}";
      };
      extraOptions = ["--network=host"];
    };
  };
}
