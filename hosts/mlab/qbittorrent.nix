{
  config,
  lib,
  services,
  ...
}: {
  sops.secrets."qbit_password_hash" = {};
  sops.secrets."qbit_password_salt" = {};

  sops.templates."qBittorrent.conf" = {
    content = ''
      [Preferences]
      WebUI\Username=${config.sops.placeholder.web_user}
      WebUI\Port=${toString services.qbit.port}
      WebUI\LocalHostAuthentication=false
      WebUI\AuthSubnetWhitelist=127.0.0.1/32,192.168.1.0/24
      Connection\AddressFamily=Both
      Connection\Interface=enp87s0
      Downloads\SavePath=/var/lib/media/downloads/
      Session\DefaultSavePath=/var/lib/media/downloads/
      Session\TempPath=/var/lib/media/downloads/incomplete/
    '';
    owner = "qbittorrent";
    group = "media";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/qbittorrent 0775 qbittorrent media -"
    "d /var/lib/qbittorrent/.config/qBittorrent 0750 qbittorrent qbittorrent -"
  ];

  services.qbittorrent = {
    enable = true;
    openFirewall = true;
    webuiPort = services.qbit.port;
  };

  users.users.qbittorrent.extraGroups = ["media"];

  systemd.services.qbittorrent = {
    preStart = ''
      # The directory structure is guaranteed by systemd.tmpfiles.rules
      cp -f ${
        config.sops.templates."qBittorrent.conf".path
      } /var/lib/qbittorrent/.config/qBittorrent/qBittorrent.conf
      # Ensure correct permissions for the copied config
      chmod 600 /var/lib/qbittorrent/.config/qBittorrent/qBittorrent.conf
    '';
    serviceConfig = {
      ReadWritePaths = ["/var/lib/media"];
      UMask = lib.mkForce "0002";
    };
  };
}
