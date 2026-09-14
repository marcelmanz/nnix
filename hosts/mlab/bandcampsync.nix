{
  pkgs,
  config,
  services,
  ...
}: let
  htmlDir = "/var/lib/bandcampsync-status";
  reportPy = ./bandcampsync_report.py;
in {
  # bandcamp cookies arrive via syncthing from laptop (see syncthing.nix)

  systemd.services.bandcampsync = {
    description = "Sync Bandcamp collection to music (flac) and dj (aiff)";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    path = [pkgs.bash pkgs.coreutils pkgs.curl pkgs.python313Packages.pipx];
    onFailure = ["bandcampsync-report.service"];
    unitConfig.OnSuccess = "bandcampsync-report.service";
    script = ''
      set -e
      # filter to bandcamp-only cookies (full-profile exports break the tool)
      grep bandcamp /var/lib/syncthing/bandcamp-cookies/cookies.txt > /run/bandcamp_cookies_filtered.txt
      chmod 400 /run/bandcamp_cookies_filtered.txt
      # fetch real bandcamp album URLs (id -> item_url) from collection metadata
      pipx run --spec bandcampsync python3 ${reportPy} fetch-urls
      # bandcampsync's collection checkpoint always advances to the newest item, and
      # the checkpoint item itself is excluded from processing. So an unreleased
      # preorder that gets skipped is never revisited once it releases. Clear the
      # state each run to force a full re-scan; the bandcamp_item_id.txt index already
      # prevents re-downloading synced albums, so the re-scan is cheap.
      rm -f /var/lib/media/music/.bandcampsync-state.json /var/lib/media/dj/.bandcampsync-state.json
      pipx run bandcampsync -c /run/bandcamp_cookies_filtered.txt -d /var/lib/media/music -f flac --skip-hidden
      pipx run bandcampsync -c /run/bandcamp_cookies_filtered.txt -d /var/lib/media/dj -f aiff-lossless --skip-hidden
      rm /run/bandcamp_cookies_filtered.txt
      # bandcampsync writes some files (e.g. bandcamp_item_id.txt) without group
      # read, which blocks syncthing (group media) from scanning dj-library
      chown -R root:media /var/lib/media/dj
      chmod -R g+rX /var/lib/media/dj
      # trigger a navidrome full scan so new tracks show up right away
      curl -fsS "http://127.0.0.1:${toString services.navidrome.port}/rest/startScan.view?u=$(cat ${config.sops.secrets.web_user.path})&t=$(cat ${config.sops.secrets.navidrome_token.path})&s=$(cat ${config.sops.secrets.navidrome_salt.path})&v=1.16.1&c=bandcampsync&f=json&fullScan=true" > /dev/null
    '';
  };

  systemd.services.bandcampsync-report = {
    description = "Generate bandcampsync status html";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Environment = "PYTHONTZPATH=${pkgs.tzdata}/share/zoneinfo";
    };
    path = [pkgs.bash pkgs.python313 pkgs.systemd];
    script = "${pkgs.python313}/bin/python3 ${reportPy} generate";
  };

  # static status page at https://bcsync.marcel.cool (added to proxy.nix)
  services.nginx.virtualHosts."bcsync.marcel.cool" = {
    forceSSL = true;
    useACMEHost = "marcel.cool";
    root = htmlDir;
    # autoindex off, and CORS so the azuracast public page (different origin) can
    # fetch links.json to turn now-playing artist names into bandcamp links.
    extraConfig = ''
      autoindex off;
      add_header Access-Control-Allow-Origin * always;
    '';
  };

  systemd.timers.bandcampsync = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = ["08:00" "16:00" "00:00"];
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };
}
