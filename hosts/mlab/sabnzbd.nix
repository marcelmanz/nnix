{
  _config,
  lib,
  services,
  ...
}: {
  sops.secrets."sabnzbd_api" = {};

  systemd.tmpfiles.rules = [
    "d /var/lib/sabnzbd 0775 sabnzbd media -"
  ];

  services.sabnzbd = {
    enable = true;
    openFirewall = true;
    configFile = null;
    group = "media";
    settings = {
      misc = {
        host_whitelist = "sabnzbd.marcel.cool, mlab, 127.0.0.1";
      };
      server = {
        host = "0.0.0.0";
        port = services.sabnzbd.port;
      };
    };
    allowConfigWrite = true;
  };

  users.users.sabnzbd = {
    extraGroups = ["media"];
  };

  systemd.services.sabnzbd.serviceConfig = {
    ReadWritePaths = ["/var/lib/media"];
    UMask = lib.mkForce "0002";
  };
}
