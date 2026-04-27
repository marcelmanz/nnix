{
  config,
  _lib,
  services,
  ...
}: {
  sops.secrets."seerr_api" = {};

  systemd.tmpfiles.rules = [
    "d /var/lib/seerr 0775 1000 media -"
  ];

  virtualisation.oci-containers.containers.seerr = {
    image = "ghcr.io/seerr-team/seerr:latest";
    volumes = [
      "/var/lib/seerr:/app/config"
    ];
    environment = {
      TZ = config.time.timeZone;
      PORT = toString services.seerr.port;
    };
    extraOptions = [
      "--network=host"
      "--init"
    ];
  };
}
