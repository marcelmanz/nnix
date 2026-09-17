{
  config,
  _lib,
  services,
  ...
}: {
  sops.secrets."tagr_secret_key" = {};

  sops.templates."tagr.env".content = ''
    DATABASE_URL=file:/data/tagr.db
    AUTH_SECRET=${config.sops.placeholder.tagr_secret_key}
    AUTH_USER=${config.sops.placeholder.web_user}
    AUTH_PASSWORD=${config.sops.placeholder.web_pass}
    AUTH_URL=${services.tagr.href}
    MUSIC_FOLDERS=/music
  '';

  systemd.tmpfiles.rules = [
    "d /var/lib/tagr 0755 root root -"
  ];

  virtualisation.oci-containers.containers.tagr = {
    image = "ghcr.io/suitux/tagr:latest";
    ports = ["127.0.0.1:${toString services.tagr.port}:3000"];
    # tagr rewrites tags in place, so it needs group write on the library.
    # bandcampsync normalizes music/ to 2775 dirs + 0664 files owned by :media
    # after every run, which is what makes uid 1000 + gid media enough here.
    environment = {
      PUID = "1000";
      PGID = toString config.users.groups.media.gid;
    };
    volumes = [
      "/var/lib/tagr:/data"
      "/var/lib/media/music:/music"
    ];
    environmentFiles = [config.sops.templates."tagr.env".path];
  };
}
