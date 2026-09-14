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
}
