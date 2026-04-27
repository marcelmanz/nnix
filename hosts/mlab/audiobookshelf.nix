{
  _config,
  _lib,
  services,
  ...
}: {
  systemd.tmpfiles.rules = [
    "d /var/lib/media/audiobooks 2775 root media -"
  ];

  services.audiobookshelf = {
    enable = true;
    port = services.audiobooks.port;
    openFirewall = true;
  };

  users.users.audiobookshelf = {
    extraGroups = ["media"];
  };
}
