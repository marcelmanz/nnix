{
  pkgs,
  config,
  services,
  ...
}: let
  library = "/var/lib/media/dj";
  stickRoot = "/var/lib/media/dj-stick";
  stickLibrary = "${stickRoot}/dj";

  # Keep djsync's own settings/state out of the USB export tree.
  stateDir = "/var/lib/dj-rekordbox";
  progressFile = "${stateDir}/progress.json";
  syncthing = config.services.syncthing;
  syncthingConfig = "${syncthing.configDir}/config.xml";

  rescanLibrary = pkgs.writeShellScript "dj-rekordbox-rescan" ''
    key=$(${pkgs.gnused}/bin/sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' ${syncthingConfig})
    ${pkgs.curl}/bin/curl -fsS -X POST -H "X-API-Key: $key" \
      "http://${syncthing.guiAddress}/rest/db/scan?folder=dj-rekordbox"
  '';

  moveInPlaceExport = pkgs.writeShellScript "dj-rekordbox-move-in-place-export" ''
    if [ -f ${library}/PIONEER/rekordbox/exportLibrary.db ] &&
      [ ! -e ${stickRoot}/PIONEER/rekordbox/exportLibrary.db ]; then
      rmdir ${stickRoot}/PIONEER 2>/dev/null || true
      for name in PIONEER DJSync_Backups .djsync-export.json; do
        if [ -e "${library}/$name" ] && [ ! -e "${stickRoot}/$name" ]; then
          mv "${library}/$name" ${stickRoot}/
        fi
      done
      rm -f ${library}/.djsync-export.lock
    fi
  '';
in {
  # Rekordbox USB export (OneLibrary exportLibrary.db + legacy export.pdb + ANLZ).
  # Copy the whole folder to a FAT32 stick, or from mlab:
  #   dj-rekordbox sync-usb --root ${stickRoot} --dest /run/media/$USER/FIESTA --delete
  environment.systemPackages = [pkgs.dj-rekordbox];

  systemd.tmpfiles.rules = [
    "d ${stickRoot} 2775 root media -"
  ];

  fileSystems.${stickLibrary} = {
    device = library;
    fsType = "none";
    options = ["bind" "ro"];
  };

  systemd.services.dj-rekordbox = {
    description = "Write a Rekordbox USB export of ${library} into ${stickRoot}";
    after = ["local-fs.target"];
    requires = ["local-fs.target"];
    unitConfig.RequiresMountsFor = [stickLibrary];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStartPre = "+${moveInPlaceExport}";
      ExecStart = "${pkgs.dj-rekordbox}/bin/dj-rekordbox export --source ${stickLibrary} --root ${stickRoot} --min-age 120 --prune --progress-file ${progressFile}";
      ExecStartPost = "-${rescanLibrary}";
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
      ReadWritePaths = [stickRoot stateDir];
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

  systemd.services.dj-rekordbox-status = {
    description = "Rekordbox export status page (${services.djexport.href})";
    after = ["network.target" "syncthing.service"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.systemd];
    serviceConfig = {
      Type = "simple";
      User = "syncthing";
      Group = "syncthing";
      ExecStart = builtins.concatStringsSep " " [
        "${pkgs.python3}/bin/python3 ${./dj-rekordbox-status.py}"
        "--port ${toString services.djexport.port}"
        "--template ${./dj-rekordbox-status.html}"
        "--progress-file ${progressFile}"
        "--syncthing-url http://${syncthing.guiAddress}"
        "--syncthing-config ${syncthingConfig}"
        "--device ${syncthing.settings.devices.nixos.id}"
        "--library-folder dj-library"
        "--export-folder dj-rekordbox"
      ];
      Restart = "on-failure";
      RestartSec = "5s";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
    };
  };
}
