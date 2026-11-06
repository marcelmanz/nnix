{pkgs, ...}: let
  lanInterface = "enp1s0";
  stateDir = "/var/lib/lan-ipv6-prefix";
in {
  systemd.services.lan-ipv6-prefix = {
    description = "Track the LAN IPv6 prefix for nginx and the firewall";
    path = [pkgs.iproute2 pkgs.coreutils pkgs.gnugrep pkgs.systemd];
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "lan-ipv6-prefix";
    };
    script = ''
      prefix=$(ip -6 route show dev ${lanInterface} proto kernel | cut -d" " -f1 | grep -v "^fe80::" | head -1 || true)
      if [ -z "$prefix" ] || [ "$prefix" = "$(cat ${stateDir}/prefix 2>/dev/null)" ]; then
        exit 0
      fi
      echo "$prefix" > ${stateDir}/prefix
      echo "allow $prefix;" > ${stateDir}/nginx-allow.conf
      systemctl --no-block try-reload-or-restart nginx.service firewall.service
    '';
  };

  systemd.timers.lan-ipv6-prefix = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "15min";
    };
  };
}
