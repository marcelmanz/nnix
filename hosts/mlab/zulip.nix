{
  config,
  pkgs,
  services,
  ...
}: let
  domain = "chat.marcel.cool";
in {
  sops.secrets."zulip_secret_key" = {};
  sops.secrets."zulip_postgres_password" = {};
  sops.secrets."zulip_rabbitmq_password" = {};

  sops.templates."zulip-db.env".content = ''
    POSTGRES_DB=zulip
    POSTGRES_USER=zulip
    POSTGRES_PASSWORD=${config.sops.placeholder.zulip_postgres_password}
  '';

  sops.templates."zulip-rabbitmq.env".content = ''
    RABBITMQ_DEFAULT_USER=zulip
    RABBITMQ_DEFAULT_PASS=${config.sops.placeholder.zulip_rabbitmq_password}
  '';

  sops.templates."zulip-app.env".content = ''
    DB_HOST=zulip-database
    DB_HOST_PORT=5432
    DB_USER=zulip
    SSL_CERTIFICATE_GENERATION=none
    SETTING_MEMCACHED_LOCATION=zulip-memcached:11211
    SETTING_RABBITMQ_HOST=zulip-rabbitmq
    SETTING_REDIS_HOST=zulip-redis
    SECRETS_rabbitmq_password=${config.sops.placeholder.zulip_rabbitmq_password}
    SECRETS_postgres_password=${config.sops.placeholder.zulip_postgres_password}
    SECRETS_secret_key=${config.sops.placeholder.zulip_secret_key}
    SETTING_EXTERNAL_HOST=${domain}
    SETTING_ZULIP_ADMINISTRATOR=admin@marcel.cool
    ZULIP_AUTH_BACKENDS=EmailAuthBackend
    # Configure SMTP when stalwart submission listener is enabled:
    # SETTING_EMAIL_HOST=127.0.0.1
    # SETTING_EMAIL_HOST_USER=noreply@marcel.cool
    # SETTING_EMAIL_PORT=587
    # SETTING_EMAIL_USE_TLS=True
    # SECRETS_email_password=
  '';

  systemd.tmpfiles.rules = [
    "d /var/lib/zulip 0755 root root -"
    "d /var/lib/zulip/postgresql 0755 root root -"
    "d /var/lib/zulip/rabbitmq 0755 root root -"
    "d /var/lib/zulip/redis 0755 root root -"
    "d /var/lib/zulip/data 0755 root root -"
  ];

  systemd.services = {
    podman-network-zulip = {
      description = "Create Podman network for Zulip";
      after = ["network.target" "podman.service" "podman.socket"];
      requires = ["podman.service" "podman.socket"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.podman}/bin/podman network inspect zulip-net >/dev/null 2>&1 || ${pkgs.podman}/bin/podman network create zulip-net'";
      };
      wantedBy = ["multi-user.target"];
    };

    "podman-zulip-database" = {
      after = ["podman-network-zulip.service"];
      requires = ["podman-network-zulip.service"];
    };
    "podman-zulip-memcached" = {
      after = ["podman-network-zulip.service"];
      requires = ["podman-network-zulip.service"];
    };
    "podman-zulip-rabbitmq" = {
      after = ["podman-network-zulip.service"];
      requires = ["podman-network-zulip.service"];
    };
    "podman-zulip-redis" = {
      after = ["podman-network-zulip.service"];
      requires = ["podman-network-zulip.service"];
    };
    "podman-zulip-app" = {
      after = ["podman-network-zulip.service"];
      requires = ["podman-network-zulip.service"];
    };
  };

  virtualisation.oci-containers.containers = {
    zulip-database = {
      image = "docker.io/zulip/zulip-postgresql:14";
      volumes = ["/var/lib/zulip/postgresql:/var/lib/postgresql/data"];
      environmentFiles = [config.sops.templates."zulip-db.env".path];
      extraOptions = ["--network=zulip-net" "--network-alias=zulip-database"];
    };

    zulip-memcached = {
      image = "docker.io/library/memcached:alpine";
      cmd = ["memcached" "-m" "128"];
      extraOptions = ["--network=zulip-net" "--network-alias=zulip-memcached"];
    };

    zulip-rabbitmq = {
      image = "docker.io/library/rabbitmq:3.13";
      volumes = ["/var/lib/zulip/rabbitmq:/var/lib/rabbitmq"];
      environmentFiles = [config.sops.templates."zulip-rabbitmq.env".path];
      extraOptions = ["--network=zulip-net" "--network-alias=zulip-rabbitmq"];
    };

    zulip-redis = {
      image = "docker.io/library/redis:alpine";
      cmd = ["redis-server" "--save" "60" "1" "--loglevel" "warning"];
      volumes = ["/var/lib/zulip/redis:/data"];
      extraOptions = ["--network=zulip-net" "--network-alias=zulip-redis"];
    };

    zulip-app = {
      image = "docker.io/zulip/docker-zulip:9.2-0";
      ports = ["127.0.0.1:${toString services.zulip.port}:80"];
      environmentFiles = [config.sops.templates."zulip-app.env".path];
      volumes = ["/var/lib/zulip/data:/data"];
      extraOptions = [
        "--network=zulip-net"
        "--ulimit=nofile=1000000:1048576"
      ];
      dependsOn = [
        "zulip-database"
        "zulip-memcached"
        "zulip-rabbitmq"
        "zulip-redis"
      ];
    };
  };
}
