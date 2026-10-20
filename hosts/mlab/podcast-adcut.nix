{pkgs, ...}: let
  # chromaprint fingerprint (fpcalc -raw) of the sting each show plays on both sides of an ad break
  shows = pkgs.writeText "podcast-adcut-shows.json" (builtins.toJSON {
    "The Rest Is Science" = [3911627774 3894851070 3894865262 3895875950 3897952751 3901042121 1757685193 1766007241 1799487961 1800536539 1800602827 1809124459 1803820139 1803822378 1804363530 1804395019 1770828299 1775022601 1758049129 1749591405 940090733 957183325 957232973 957223757 688784253 692979557 680478053 680314213 679798087 679781703 700818759];
  });
  python = pkgs.python3.withPackages (p: [p.numpy]);
in {
  systemd.services.podcast-adcut = {
    description = "Cut inserted ad breaks out of downloaded podcast episodes";
    path = [pkgs.chromaprint pkgs.ffmpeg];
    environment = {
      PODCAST_DIR = "/var/lib/media/podcasts";
      SHOWS_FILE = "${shows}";
      # logs the planned cuts without touching the files
      DRY_RUN = "1";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "audiobookshelf";
      StateDirectory = "podcast-adcut";
      ExecStart = "${python}/bin/python3 ${./podcast-adcut.py}";
    };
  };

  systemd.timers.podcast-adcut = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };
}
