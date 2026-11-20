{
  pkgs,
  ...
}: let
  source = "/var/lib/media/dj";
  exportRoot = "/var/lib/media/dj-rekordbox";

  # Keep djsync's own settings/state out of the USB export tree.
  stateDir = "/var/lib/dj-rekordbox";
in {
  # Rekordbox USB export (OneLibrary exportLibrary.db + legacy export.pdb + ANLZ).
  # The export is a normal stick image; sync-usb copies it to a mounted FAT32 stick:
  #   dj-rekordbox sync-usb --dest /run/media/$USER/CDJ --delete
  environment.systemPackages = [pkgs.dj-rekordbox];

  systemd.tmpfiles.rules = [
    "d ${exportRoot} 2775 root media -"
  ];

  systemd.services.dj-rekordbox = {
    description = "Mirror ${source} into a Rekordbox USB export";
    after = ["local-fs.target"];
    requires = ["local-fs.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = "${pkgs.dj-rekordbox}/bin/dj-rekordbox export --source ${source} --root ${exportRoot} --min-age 120 --prune";
      StateDirectory = "dj-rekordbox";
      Environment = "DJSYNC_HOME=${stateDir}";
      # First export analyses every track; a large library can take a while.
      TimeoutStartSec = "6h";
      Nice = 10;
      IOSchedulingClass = "idle";
      # Hardening: only the export/state trees are writable.
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadWritePaths = [exportRoot stateDir];
    };
  };

  # Timer rather than systemd.path: path units do not recurse, and Syncthing
  # writes into existing album folders. The exporter skips unchanged files by
  # stat, so a 30-minute poll is cheap.
  systemd.timers.dj-rekordbox = {
    description = "Periodically refresh the Rekordbox USB export";
    wantedBy = ["timers.target"];
    timerConfig = {
      Unit = "dj-rekordbox.service";
      OnBootSec = "10m";
      OnUnitActiveSec = "30m";
      RandomizedDelaySec = "2m";
    };
  };
}
