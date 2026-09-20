{
  config,
  lib,
  services,
  ...
}: let
  slskdSettings = {
    directories = {
      downloads = "/var/lib/slskd/music/downloads";
      incomplete = "/var/lib/slskd/music/incompleted";
    };
    shares = {
      directories = ["/var/lib/slskd/music/share"];
    };
    soulseek = {
      listen_port = 50300;
    };
    web = {
      port = services.slskd.port;
      address = "127.0.0.1"; # nginx fronts the web UI
    };
    transfers = {
      upload.slots = 10;
      download.slots = 10;
    };
  };
in {
  sops.secrets."slsk_pass" = {};
  sops.secrets."slsk_user" = {};
  sops.secrets."slskd_api_key" = {};

  sops.templates."slskd-mlab.env" = {
    content = ''
      APP_DIR=/var/lib/slskd

      SLSKD_SLSK_USERNAME='${config.sops.placeholder.slsk_user}'
      SLSKD_SLSK_PASSWORD='${config.sops.placeholder.slsk_pass}'

      SLSKD_USERNAME='${config.sops.placeholder.web_user}'
      SLSKD_PASSWORD='${config.sops.placeholder.web_pass}'

      SLSKD_WEB_USERNAME=${config.sops.placeholder.web_user}
      SLSKD_WEB_PASSWORD=${config.sops.placeholder.web_pass}
    '';
    owner = "slskd";
  };

  # api_keys can only come from the config file, so render the whole file with
  # sops instead of letting the module leave it world-readable in the nix store.
  sops.templates."slskd-mlab.yml" = {
    content = builtins.toJSON (lib.recursiveUpdate slskdSettings {
      web.authentication.api_keys.soulbeet = {
        key = config.sops.placeholder.slskd_api_key;
        role = "readwrite";
        cidr = "127.0.0.1/32,::1/128";
      };
    });
    owner = "slskd";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/slskd 0755 slskd slskd -"
    "d /var/lib/slskd/music 0755 slskd slskd -"
    "d /var/lib/slskd/music/downloads 0755 slskd slskd -"
    "d /var/lib/slskd/music/incompleted 0755 slskd slskd -"
    "d /etc/slskd 0755 slskd slskd -"
    "d /var/lib/slskd/music/share 0775 slskd media -"
  ];

  services.slskd = {
    enable = true;
    openFirewall = true;
    domain = null;
    user = "slskd";
    group = "slskd";
    environmentFile = config.sops.templates."slskd-mlab.env".path;
    settings = slskdSettings;
  };

  users.users.slskd = {
    isSystemUser = true;
    group = "slskd";
    home = "/var/lib/slskd";
    createHome = true;
  };
  users.groups.slskd = {};

  systemd.services.slskd.serviceConfig = {
    ExecStart = lib.mkForce "${config.services.slskd.package}/bin/slskd --app-dir /var/lib/slskd --config ${config.sops.templates."slskd-mlab.yml".path}";
    Restart = lib.mkForce "always";
    RestartSec = "5s";
    StateDirectory = "slskd";
    WorkingDirectory = "/var/lib/slskd";
    UMask = "0022";
  };
}
