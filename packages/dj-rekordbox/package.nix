{pkgs}: let
  djsync = import ../djsync/package.nix {inherit pkgs;};
  python = pkgs.python313.withPackages (ps: [djsync]);
in
  pkgs.writeShellApplication {
    name = "dj-rekordbox";
    runtimeInputs = [
      python
      pkgs.ffmpeg-headless
      pkgs.rsync
      pkgs.coreutils
    ];
    text = ''
      exec python3 ${./dj-rekordbox-export.py} "$@"
    '';
    meta = with pkgs.lib; {
      description = "Mirror a DJ folder into a Rekordbox USB export and copy it to a FAT32 stick";
      license = licenses.gpl3Only;
      mainProgram = "dj-rekordbox";
      platforms = platforms.linux;
    };
  }
