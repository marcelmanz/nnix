{
  _config,
  _lib,
  services,
  ...
}: {
  systemd.tmpfiles.rules = [
    "d /var/lib/media/audiobooks 2775 root media -"
    "d /var/lib/media/podcasts 2775 root media -"
  ];

  services.audiobookshelf = {
    enable = true;
    port = services.audiobooks.port;
    openFirewall = false; # nginx fronts this
  };

  users.users.audiobookshelf = {
    extraGroups = ["media"];
  };
}
