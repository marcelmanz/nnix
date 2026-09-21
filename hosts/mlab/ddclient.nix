{
  config,
  pkgs,
  _lib,
  _services,
  ...
}: let
  # networkd hands enp1s0 a stable SLAAC address (ipv6AcceptRAConfig.Token =
  # "prefixstable", flagged mngtmpaddr) plus a temporary privacy address that rotates
  # every 24h. The mngtmpaddr flag selects the stable one - publishing the temporary
  # address instead churns the AAAA daily and leaks what privacy extensions exist to hide.
  stableIPv6 = pkgs.writeShellApplication {
    name = "mlab-stable-ipv6";
    runtimeInputs = [pkgs.iproute2 pkgs.gawk];
    text = ''
      ip -6 -o addr show dev enp1s0 scope global mngtmpaddr | awk '{split($4, a, "/"); print a[1]}'
    '';
  };
in {
  sops.secrets."cloudflare_ddclient_token" = {
    owner = "ddclient";
    group = "ddclient";
  };

  services.ddclient = {
    enable = true;
    interval = "5min";
    protocol = "cloudflare";
    zone = "marcel.cool";
    username = "token";
    passwordFile = config.sops.secrets.cloudflare_ddclient_token.path;
    # single source of truth = ssh.marcel.cool. The module's usev6 default asks
    # api6.ipify.org for the outbound source address, which is the rotating temporary one -
    # read the stable address off the interface instead. Rotation itself stays on for
    # invidious egress; only what gets published changes.
    domains = ["ssh.marcel.cool" "marcel.cool"];
    usev4 = "webv4, webv4=ifconfig.me";
    usev6 = "cmdv6, cmdv6=${stableIPv6}/bin/mlab-stable-ipv6";
    ssl = true;
  };

  users.users.ddclient = {
    isSystemUser = true;
    group = "ddclient";
  };
  users.groups.ddclient = {};

  systemd.services.ddclient.after = ["nss-user-lookup.target"];
}
