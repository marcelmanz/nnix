# Rotates the host's IPv6 source address used for Google/YouTube egress, so
# invidious doesn't keep hammering YouTube from the same address forever.
# Reimplements iv-org/smart-ipv6-rotator's core (pick a random address in the
# host's own /64, route Google's IPv6 ranges via it) in plain iproute2 instead
# of vendoring the upstream python+pyroute2 tool.
{
  pkgs,
  lib,
  ...
}: let
  # Google's IPv6 ranges (covers youtube.com/googlevideo.com) - from
  # iv-org/smart-ipv6-rotator's default "google" service list.
  googleRanges = [
    "2001:4860::/32"
    "2404:6800::/32"
    "2404:f340::/32"
    "2600:1900::/28"
    "2605:ef80::/32"
    "2606:40::/32"
    "2606:73c0::/32"
    "2607:1c0:241:40::/60"
    "2607:1c0:300::/40"
    "2607:f8b0::/32"
    "2620:11a:a000::/40"
    "2620:120:e000::/40"
    "2800:3f0::/32"
    "2a00:1450::/32"
    "2c0f:fb50::/32"
  ];

  ipv6-rotate = pkgs.writeShellApplication {
    name = "ipv6-rotate";
    runtimeInputs = with pkgs; [iproute2 gawk coreutils];
    text = ''
      stateFile=/run/ipv6-rotate/address

      # token-scan rather than fixed field positions - iproute2 inserts an
      # optional "nhid <id>" token before "via" when the route has a named
      # nexthop, which shifts every fixed column after it.
      defaultRoute=$(ip -6 route show default | head -1)
      iface=$(awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}' <<<"$defaultRoute")
      gateway=$(awk '{for (i=1;i<=NF;i++) if ($i=="via") {print $(i+1); exit}}' <<<"$defaultRoute")
      if [ -z "$iface" ] || [ -z "$gateway" ]; then
        echo "ipv6-rotate: no default IPv6 route found" >&2
        exit 1
      fi

      prefix=$(ip -6 addr show dev "$iface" scope global \
        | awk '/inet6/{print $2; exit}' | cut -d/ -f1 | awk -F: '{print $1":"$2":"$3":"$4}')
      if [ -z "$prefix" ]; then
        echo "ipv6-rotate: no global IPv6 address found on $iface" >&2
        exit 1
      fi

      if [ -s "$stateFile" ]; then
        oldAddr=$(cat "$stateFile")
        for range in ${lib.concatStringsSep " " googleRanges}; do
          ip -6 route del "$range" src "$oldAddr" dev "$iface" 2>/dev/null || true
        done
        ip -6 addr del "$oldAddr/64" dev "$iface" 2>/dev/null || true
      fi

      suffix=$(od -An -N8 -tx2 /dev/urandom | tr -d ' \n' | sed -E 's/(.{4})(.{4})(.{4})(.{4})/\1:\2:\3:\4/')
      newAddr="$prefix:$suffix"

      ip -6 addr add "$newAddr/64" dev "$iface"
      sleep 2 # let the kernel take the new address into account before routing via it

      for range in ${lib.concatStringsSep " " googleRanges}; do
        ip -6 route replace "$range" src "$newAddr" via "$gateway" dev "$iface"
      done

      echo "$newAddr" > "$stateFile"
      echo "ipv6-rotate: now using $newAddr for google/youtube egress"
    '';
  };
in {
  systemd.services.ipv6-rotate = {
    description = "Rotate the source IPv6 address used for Google/YouTube egress (invidious anti-block)";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "ipv6-rotate";
      ExecStart = lib.getExe ipv6-rotate;
    };
  };

  systemd.timers.ipv6-rotate = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "12h";
      Persistent = true;
    };
  };
}
