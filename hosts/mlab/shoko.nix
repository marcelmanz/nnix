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

  systemd.services.shoko.serviceConfig.Environment = [
    "AVDUMP_PATH=${pkgs.avdump3}/bin/avdump3"
  ];

  # inject 'media' group access directly into the systemd service
  systemd.services.shoko.serviceConfig = {
    SupplementaryGroups = ["media"];
    ReadWritePaths = ["/var/lib/media"];
    UMask = lib.mkForce "0002";
  };
}
