{
  config,
  lib,
  services,
  ...
}: let
  # sonarr/radarr are pia-confined; the host reaches them on the namespace address.
  arrUrl = svc: "http://${config.vpnNamespaces.pia.namespaceAddress}:${toString services.${svc}.port}";
in {
  # Scene torrents arrive as rar sets that sonarr/radarr can't import; unpackerr extracts them
  # next to the archive, waits for the import, then removes the extracted copy.
  sops.templates."unpackerr-env".content = ''
    UN_SONARR_0_URL=${arrUrl "sonarr"}
    UN_SONARR_0_API_KEY=${config.sops.placeholder.sonarr_api}
    UN_RADARR_0_URL=${arrUrl "radarr"}
    UN_RADARR_0_API_KEY=${config.sops.placeholder.radarr_api}
  '';

  services.unpackerr = {
    enable = true;
    group = "media";
    # group-writable so sonarr/radarr (media group) can hardlink/move the extracted files
    settings = {
      file_mode = "0664";
      dir_mode = "0775";
    };
  };

  systemd.services.unpackerr = {
    after = ["sonarr.service" "radarr.service"];
    serviceConfig = {
      EnvironmentFile = [config.sops.templates."unpackerr-env".path];
      UMask = lib.mkForce "0002";
    };
  };
}
