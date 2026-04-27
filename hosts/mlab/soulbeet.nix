{
  config,
  pkgs,
  _lib,
  services,
  ...
}: {
  sops.secrets."soulbeet_secret_key" = {};

  sops.templates."soulbeet.env".content = ''
    SLSKD_URL=http://127.0.0.1:${toString services.slskd.port}
    # SLSKD_API_KEY=${config.sops.placeholder.slskd_api_key}
    NAVIDROME_URL=http://127.0.0.1:${toString services.navidrome.port}
    NAVIDROME_USERNAME=${config.sops.placeholder.web_user}
    NAVIDROME_PASSWORD=${config.sops.placeholder.web_pass}
    SECRET_KEY=${config.sops.placeholder.soulbeet_secret_key}
    DATABASE_URL=sqlite:/data/soulbeet.db
    DOWNLOAD_PATH=/var/lib/slskd/music/downloads
    NAVIDROME_MUSIC_PATH=/music
    SOULBEET_URL=https://soulbeet.marcel.cool
  '';

  systemd.tmpfiles.rules = [
    "d /var/lib/soulbeet 0755 root root -"
  ];

  environment.etc."soulbeet/beets_config.yaml".text = ''
    directory: /music
    library: /data/soulbeet.db

    plugins: fromfilename

    import:
      move: yes
      write: yes
      quiet_fallback: asis
  '';

  virtualisation.oci-containers.containers.soulbeet = {
    image = "docker.io/docccccc/soulbeet:latest";
    environment = {
      BEETSDIR = "/config";
    };
    volumes = [
      "/var/lib/soulbeet:/data"
      "/var/lib/slskd/music/downloads:/var/lib/slskd/music/downloads"
      "/var/lib/slskd/music/share:/music"
      "/etc/soulbeet/beets_config.yaml:/config/config.yaml"
    ];
    environmentFiles = [
      config.sops.templates."soulbeet.env".path
    ];
    extraOptions = ["--network=host"]; # allows easy access to local slskd/navidrome
  };

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "import-music" ''
      if [ -z "$1" ]; then
        echo "No specific folder provided. Importing EVERYTHING in downloads..."
        sudo podman exec -it soulbeet beet import /var/lib/slskd/music/downloads
      else
        echo "Importing: $1"
        sudo podman exec -i soulbeet beet import "/var/lib/slskd/music/downloads/$1"
      fi
    '')
  ];
}
