{
  _config,
  pkgs,
  lib,
  ...
}: {
  services.shoko = {
    enable = true;
    openFirewall = true;
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/media/anime 2775 root media -"
    "d /var/lib/media/downloads/anime 2775 root media -"
  ];

  environment.systemPackages = with pkgs; [
    avdump3
    dotnet-sdk_11
  ];

  # Shoko hardcodes `<SHOKO_HOME>/AVDump3/AVDump3` and ignores AVDUMP_PATH,
  # so its auto-updater tries to download a non-FHS binary that can't run on
  # NixOS. Symlink the nix avdump3 into the hardcoded path before start.
  # ponytail: shoko module sets StateDirectory=shoko (=/var/lib/shoko, writable
  # by the shoko user); preStart runs as that user, so mkdir+ln succeed.
  systemd.services.shoko = {
    preStart = ''
      mkdir -p /var/lib/shoko/AVDump3
      ln -sf ${pkgs.avdump3}/bin/avdump3 /var/lib/shoko/AVDump3/AVDump3
    '';

    serviceConfig = {
      SupplementaryGroups = ["media"];
      ReadWritePaths = ["/var/lib/media"];
      UMask = lib.mkForce "0002";
    };
  };
}
