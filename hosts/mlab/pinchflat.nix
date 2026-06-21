{
  lib,
  services,
  ...
}: {
  # ponytail: authelia fronts this (protected=true in proxy.nix), so no BASIC_AUTH.
  # selfhosted=true satisfies the module assertion (SECRET_KEY_BASE falls back to
  # the bundled weak default — fine behind authelia on a LAN). Drop selfhosted +
  # add a secretsFile with a real SECRET_KEY_BASE if this ever faces the public net.
  services.pinchflat = {
    enable = true;
    openFirewall = true;
    port = services.pinchflat.port;
    mediaDir = "/var/lib/media/youtube";
    selfhosted = true;
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/media/youtube 2775 root media -"
  ];

  users.users.pinchflat.extraGroups = ["media"];

  systemd.services.pinchflat.serviceConfig = {
    ReadWritePaths = ["/var/lib/media"];
    UMask = lib.mkForce "0002";
  };
}
