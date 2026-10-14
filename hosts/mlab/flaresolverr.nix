# FlareSolverr - solves Cloudflare "managed challenge" pages for indexers
# that have no API (RuTracker's /forum/login.php 403s non-browser logins
# outright). Prowlarr posts the login URL here, gets back a valid
# cf_clearance + session cookie, and uses those for subsequent requests.
#
# Prowlarr runs inside the "pia" netns, so it reaches this via the bridge
# address (192.168.16.5) - same path it uses for SABnzbd, and the bridge is
# already in allowedEgress; only the host-side INPUT rule below is new.
#
# Prowlarr setup (manual): Settings -> Indexer Proxies -> add FlareSolverr,
# host http://192.168.16.5:8191, tag e.g. "flaresolverr", then add that tag
# to the RuTracker indexer.
{
  config,
  _pkgs,
  lib,
  ...
}: let
  port = 8191;
  piaNamespaceAddress = config.vpnNamespaces.pia.namespaceAddress;
in {
  virtualisation.oci-containers.containers.flaresolverr = {
    image = "ghcr.io/flaresolverr/flaresolverr:v3.4.2";
    extraOptions = [
      "--network=host"
      # headless chromium default shm is too small for challenge pages
      "--shm-size=256m"
    ];
    environment = {
      LOG_LEVEL = "info";
      TZ = config.time.timeZone;
    };
  };

  networking.firewall.extraCommands = ''
    # guarded with -C: extraCommands appends straight to INPUT, an unguarded
    # -A would stack a duplicate on every firewall reload.
    iptables -C INPUT -s ${piaNamespaceAddress} -p tcp --dport ${toString port} -j ACCEPT 2>/dev/null \
      || iptables -A INPUT -s ${piaNamespaceAddress} -p tcp --dport ${toString port} -j ACCEPT
  '';
}
