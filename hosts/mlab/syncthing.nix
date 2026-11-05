{config, ...}: {
  # syncthing needs group write access to write into bandcampsync's root-owned dj dir
  users.users.syncthing.extraGroups = ["media"];

  services.syncthing = {
    enable = true;
    openDefaultPorts = true;
    guiAddress = "127.0.0.1:8384";
    settings.gui = {
      # proxy passes sync.marcel.cool Host header; allow it by disabling checks
      insecureSkipHostcheck = true;
      insecureAdminAccess = false;
    };
    # devices/folders added via the web UI once, they land in
    # /var/lib/syncthing/.config/syncthing/config.xml and persist
    dataDir = "/var/lib/syncthing";
  };

  # GUI reachable behind authelia via https://sync.marcel.cool (see proxy.nix).
  # First time: set a GUI password there once, otherwise any authelia user can
  # add folders/devices blindly.

  # laptop (nixos) — declared so folders can reference it
  services.syncthing.settings.devices."nixos".id = "4Z6PWTX-M7X4NZM-UOHKC5L-PBMP3II-LSY5XVR-X7GRWW4-I3UBR33-L3HK4QW";

  # bandcamp cookies export from laptop (laptop side is sendonly)
  services.syncthing.settings.folders."bandcamp-cookies" = {
    path = "/var/lib/syncthing/bandcamp-cookies";
    id = "bandcamp-cookies";
    devices = ["nixos"];
    type = "receiveonly";
  };

  # dj library (aiff, written by bandcampsync) shared to laptop for Mixxx
  services.syncthing.settings.folders."dj-library" = {
    path = "/var/lib/media/dj";
    id = "dj-library";
    devices = ["nixos"];
    type = "sendonly";
  };

  # live show recordings (mkv, written by azuracast-live-record) shared to laptop.
  # No extra permissions needed: the dir is 2775 root:media like dj above, and the
  # syncthing user is already in media. A show still being recorded syncs as it grows.
  services.syncthing.settings.folders."live-recordings" = {
    path = "/var/lib/media/live-recordings";
    id = "live-recordings";
    devices = ["nixos"];
    type = "sendonly";
  };

  services.syncthing.settings.folders."immich-upload" = {
    path = "/var/lib/syncthing/immich/upload";
    id = "immich-upload";
    devices = ["nixos"];
    type = "sendonly";
    markerName = ".immich";
  };

  services.syncthing.settings.folders."immich-db-backups" = {
    path = "/var/lib/syncthing/immich/backups";
    id = "immich-db-backups";
    devices = ["nixos"];
    type = "sendonly";
    markerName = ".immich";
  };

  fileSystems."/var/lib/syncthing/immich/upload" = {
    device = "/var/lib/immich/upload";
    fsType = "none";
    options = ["bind" "ro"];
  };

  fileSystems."/var/lib/syncthing/immich/backups" = {
    device = "/var/lib/immich/backups";
    fsType = "none";
    options = ["bind" "ro"];
  };

  systemd.tmpfiles.rules = [
    "A+ /var/lib/immich/upload - - - - u:syncthing:rX,d:u:syncthing:rX"
    "A+ /var/lib/immich/backups - - - - u:syncthing:rX,d:u:syncthing:rX"
  ];
}
