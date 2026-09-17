{
  pkgs,
  services,
  ...
}: let
  configFile = (pkgs.formats.yaml {}).generate "filebrowser-quantum.yaml" {
    server = {
      listen = "127.0.0.1";
      port = services.files.port;
      externalUrl = services.files.href;
      database = "/var/lib/filebrowser-quantum/database.db";
      cacheDir = "/var/cache/filebrowser-quantum";

      # New files land group-writable so bandcampsync, azuracast and syncthing
      # keep working on anything uploaded here. No setgid bit here on purpose:
      # RestrictSUIDSGID below makes any mkdir that sets it fail with EPERM, and
      # the media dirs are already 2775, so subdirs inherit setgid from the parent.
      filesystem = {
        createFilePermission = "664";
        createDirectoryPermission = "775";
      };

      # Multiple roots, no bind mounts. defaultEnabled must be set explicitly:
      # it is only implied when there is exactly one source.
      sources = [
        {
          path = "/var/lib/media/live-recordings";
          name = "live-recordings";
          config.defaultEnabled = true;
        }
        {
          path = "/var/lib/media/dj";
          name = "dj-library";
          # bandcampsync owns this tree and syncthing mirrors it to the laptop.
          # Add `config.readOnly = true;` to make it look-but-don't-touch.
          config.defaultEnabled = true;
        }
      ];
    };

    auth = {
      # nginx gates the vhost with authelia and passes the username in Remote-User.
      # A proxy user whose name matches adminUsername is made admin on first login.
      adminUsername = "authelia";
      methods = {
        password.enabled = false;
        proxy = {
          enabled = true;
          header = "Remote-User";
        };
      };
    };

    # video/audio thumbnails and metadata
    integrations.media.ffmpegPath = "${pkgs.ffmpeg_7}/bin";

    frontend.name = "mlab files";

    userDefaults.account.permissions = {
      modify = true;
      delete = true;
      share = true;
      realtime = true;
    };
  };
in {
  users.users.filebrowser = {
    isSystemUser = true;
    group = "filebrowser";
    # same trick as syncthing: group write into the root-owned media dirs
    extraGroups = ["media"];
  };
  users.groups.filebrowser = {};

  systemd.services.filebrowser = {
    description = "FileBrowser Quantum";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      ExecStart = "${pkgs.filebrowser-quantum}/bin/filebrowser-quantum -c ${configFile}";
      User = "filebrowser";
      Group = "filebrowser";
      StateDirectory = "filebrowser-quantum";
      CacheDirectory = "filebrowser-quantum";
      WorkingDirectory = "/var/lib/filebrowser-quantum";
      UMask = "0002";
      Restart = "on-failure";

      NoNewPrivileges = true;
      PrivateDevices = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [
        "/var/lib/media/live-recordings"
        "/var/lib/media/dj"
      ];
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      LockPersonality = true;
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
    };
  };
}
