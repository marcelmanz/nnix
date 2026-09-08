# PIA WireGuard tunnel with port forwarding, covering the whole
# download/arr stack. PIA is the only VPN provider - Mullvad
# doesn't offer port forwarding any more, and qbittorrent needs an actually
# reachable inbound port for seeding to work well, so everything moved here
# rather than splitting providers.
#
# There's no static config download like Mullvad's: you register an
# ephemeral WireGuard key through PIA's API
# (https://github.com/pia-foss/manual-connections is the reference this is
# based on), and the forwarded port has to be re-bound roughly every 15
# minutes or it expires - pia-wg-config and pia-portfwd below handle both.
#
# Setup:
# 1. sops secrets/mlab.yaml -> add `pia_user`/`pia_pass` with your PIA
#    account login (the "pXXXXXXX" username PIA emails you, not your email).
# 2. nixos-rebuild switch --flake .#mlab
{
  config,
  pkgs,
  lib,
  services,
  ...
}: let
  piaAddress = "192.168.16.1";
  piaBridgeAddress = "192.168.16.5";

  piaConfined = {
    enable = true;
    vpnNamespace = "pia";
  };

  pia-wg-config = pkgs.writeShellApplication {
    name = "pia-wg-config";
    runtimeInputs = with pkgs; [curl jq wireguard-tools];
    text = ''
      umask 077

      # -f (fail-on-HTTP-error) is deliberately NOT used below: combined with
      # set -e it would kill the script at the curl call itself, before the
      # status checks below ever run - hiding the actual response body that
      # explains why. `|| exit 1` after each curl still stops on a real
      # transport failure (DNS/connect/TLS), just with a message.

      tokenResponse=$(curl -s --location --request POST \
        'https://www.privateinternetaccess.com/api/client/v2/token' \
        --form "username=$(cat ${config.sops.secrets."pia_user".path})" \
        --form "password=$(cat ${config.sops.secrets."pia_pass".path})") || {
        echo "pia-wg-config: could not reach the PIA token endpoint" >&2
        exit 1
      }
      token=$(echo "$tokenResponse" | jq -r '.token')
      if [ -z "$token" ] || [ "$token" = "null" ]; then
        echo "pia-wg-config: authentication failed: $tokenResponse" >&2
        exit 1
      fi

      regions=$(curl -s https://serverlist.piaservers.net/vpninfo/servers/v6 | head -1) || {
        echo "pia-wg-config: could not reach the PIA server list" >&2
        exit 1
      }
      wgHost=$(echo "$regions" | jq -r '[.regions[] | select(.port_forward==true)][0].servers.wg[0].cn')
      wgIp=$(echo "$regions" | jq -r '[.regions[] | select(.port_forward==true)][0].servers.wg[0].ip')
      if [ -z "$wgHost" ] || [ "$wgHost" = "null" ]; then
        echo "pia-wg-config: no port-forward-capable region found" >&2
        exit 1
      fi

      privKey=$(wg genkey)
      pubKey=$(echo "$privKey" | wg pubkey)

      wgJson=$(curl -s -G \
        --connect-to "$wgHost::$wgIp:" \
        --cacert ${./pia-ca.crt} \
        --data-urlencode "pt=$token" \
        --data-urlencode "pubkey=$pubKey" \
        "https://$wgHost:1337/addKey") || {
        echo "pia-wg-config: could not reach $wgHost:1337/addKey" >&2
        exit 1
      }
      if [ "$(echo "$wgJson" | jq -r '.status')" != "OK" ]; then
        echo "pia-wg-config: addKey failed: $wgJson" >&2
        exit 1
      fi

      cat > /run/pia/wg.conf <<CONF
      [Interface]
      Address = $(echo "$wgJson" | jq -r '.peer_ip')
      PrivateKey = $privKey
      DNS = $(echo "$wgJson" | jq -r '.dns_servers[0]')
      FwMark = 51888
      [Peer]
      PersistentKeepalive = 25
      PublicKey = $(echo "$wgJson" | jq -r '.server_key')
      AllowedIPs = 0.0.0.0/0
      Endpoint = $wgIp:$(echo "$wgJson" | jq -r '.server_port')
      CONF

      echo "$wgHost" > /run/pia/gateway_hostname
      echo "$wgIp" > /run/pia/gateway_ip
      echo "$token" > /run/pia/token
    '';
  };

  # Runs INSIDE the "pia" namespace (vpnConfinement below) - PIA's
  # getSignature/bindPort calls have to come from the already-authenticated
  # tunnel session (unlike addKey, which only needs the account token and
  # runs unconfined). That also means qbittorrent is reachable over plain
  # loopback here, since it's confined to the same namespace.
  pia-portfwd = pkgs.writeShellApplication {
    name = "pia-portfwd";
    runtimeInputs = with pkgs; [curl jq iptables];
    text = ''
      wgHost=$(cat /run/pia/gateway_hostname)
      wgIp=$(cat /run/pia/gateway_ip)
      token=$(cat /run/pia/token)

      # see the comment in pia-wg-config for why -f isn't used here.
      payloadAndSignature=$(curl -s -m 5 \
        --connect-to "$wgHost::$wgIp:" \
        --cacert ${./pia-ca.crt} \
        -G --data-urlencode "token=$token" \
        "https://$wgHost:19999/getSignature") || {
        echo "pia-portfwd: could not reach $wgHost:19999/getSignature" >&2
        exit 1
      }
      if [ "$(echo "$payloadAndSignature" | jq -r '.status')" != "OK" ]; then
        echo "pia-portfwd: getSignature failed: $payloadAndSignature" >&2
        exit 1
      fi

      signature=$(echo "$payloadAndSignature" | jq -r '.signature')
      payload=$(echo "$payloadAndSignature" | jq -r '.payload')
      port=$(echo "$payload" | base64 -d | jq -r '.port')

      bindPort() {
        bindResponse=$(curl -Gs -m 5 \
          --connect-to "$wgHost::$wgIp:" \
          --cacert ${./pia-ca.crt} \
          --data-urlencode "payload=$payload" \
          --data-urlencode "signature=$signature" \
          "https://$wgHost:19999/bindPort") || {
          echo "pia-portfwd: could not reach $wgHost:19999/bindPort" >&2
          return 1
        }
        if [ "$(echo "$bindResponse" | jq -r '.status')" != "OK" ]; then
          echo "pia-portfwd: bindPort failed: $bindResponse" >&2
          return 1
        fi
      }

      if ! bindPort; then
        echo "pia-portfwd: initial bindPort failed" >&2
        exit 1
      fi
      echo "pia-portfwd: bound port $port"

      # ponytail: the ACCEPT rule for a previous port is never removed on a
      # pia-portfwd-only restart (a stale open port, not a functional bug) -
      # add cleanup if that matters to you. A "pia.service" restart recreates
      # the whole namespace/firewall from scratch, so it doesn't accumulate there.
      iptables -A INPUT -i pia0 -p tcp --dport "$port" -j ACCEPT
      iptables -A INPUT -i pia0 -p udp --dport "$port" -j ACCEPT

      qbitUrl="http://127.0.0.1:${toString services.qbit.port}"
      # a successful login is an empty-body 204 on current qbittorrent
      # versions (older ones return 200 with body "Ok.") - check the status
      # code, not the body, so this doesn't break across version upgrades.
      loginStatus=$(curl -s -m 10 -o /dev/null -w '%{http_code}' -c /run/pia/qbit-cookie \
        -H "Referer: $qbitUrl" \
        --data-urlencode "username=$(cat ${config.sops.secrets."web_user".path})" \
        --data-urlencode "password=$(cat ${config.sops.secrets."web_pass".path})" \
        "$qbitUrl/api/v2/auth/login") || {
        echo "pia-portfwd: could not reach qbittorrent's WebUI at $qbitUrl" >&2
        exit 1
      }
      if [ "$loginStatus" != "200" ] && [ "$loginStatus" != "204" ]; then
        echo "pia-portfwd: qbittorrent login failed: HTTP $loginStatus" >&2
        exit 1
      fi
      curl -s -m 10 -b /run/pia/qbit-cookie \
        -H "Referer: $qbitUrl" \
        --data-urlencode "json={\"listen_port\": $port}" \
        "$qbitUrl/api/v2/app/setPreferences"
      echo "pia-portfwd: set qbittorrent listen_port to $port"

      while true; do
        sleep 900
        if ! bindPort; then
          echo "pia-portfwd: bindPort renewal failed, exiting for systemd to restart" >&2
          exit 1
        fi
        echo "pia-portfwd: renewed port $port at $(date -Is)"
      done
    '';
  };

  # vpn-confinement sets the netns's default route to "dev pia0" (the
  # WireGuard interface itself) for everything, which also captures the
  # WireGuard driver's OWN outer UDP packets to its peer - a circular route
  # ("ip route get <endpoint>" resolves back through pia0), so the handshake
  # never completes and no data ever comes back.
  #
  # A plain destination route fixes the handshake but ALSO diverts
  # pia-portfwd's own TCP calls to the same IP (getSignature/bindPort) around
  # the tunnel entirely - which breaks them the other way, since those calls
  # specifically need to look like they're coming from inside the
  # authenticated tunnel session (see the "Unauthorized client" issue this
  # was built around). Only the WG driver's own transport packets should
  # escape via the bridge, not our own app-level calls to the same IP.
  #
  # An external iptables mangle rule matching by IP/port turned out NOT to
  # reliably catch WireGuard's own internally-generated packets (they didn't
  # show up in mangle OUTPUT counters at all, even after forcing a handshake
  # attempt) - WireGuard has a dedicated native mechanism for exactly this
  # instead: the FwMark interface setting (set on the [Interface] section in
  # pia-wg-config's wg.conf), which the kernel driver stamps onto its own
  # packets directly, no netfilter matching needed. This is the same
  # mechanism wg-quick's own Table=auto policy routing relies on -
  # vpn-confinement's netns just doesn't set it up itself.
  pia-escape-route = pkgs.writeShellApplication {
    name = "pia-escape-route";
    runtimeInputs = with pkgs; [iproute2 iptables];
    text = ''
      wgIp=$(cat /run/pia/gateway_ip)
      mark=51888

      ip -n pia rule add fwmark "$mark" table "$mark" 2>/dev/null || true
      ip -n pia route replace default via ${piaBridgeAddress} dev veth-pia table "$mark"

      ip netns exec pia iptables -C OUTPUT -o veth-pia -d "$wgIp" -j ACCEPT 2>/dev/null \
        || ip netns exec pia iptables -I OUTPUT 1 -o veth-pia -d "$wgIp" -j ACCEPT
      iptables -t nat -C POSTROUTING -s ${piaAddress} -d "$wgIp" -j MASQUERADE 2>/dev/null \
        || iptables -t nat -A POSTROUTING -s ${piaAddress} -d "$wgIp" -j MASQUERADE
    '';
  };
in {
  sops.secrets."pia_user" = {};
  sops.secrets."pia_pass" = {};

  vpnNamespaces.pia = {
    enable = true;
    namespaceAddress = piaAddress;
    bridgeAddress = piaBridgeAddress;
    wireguardConfigFile = "/run/pia/wg.conf";
    # One portMapping per proxy.nix service tagged `vpn = "pia"` - keeps the
    # port list in one place instead of duplicating it here.
    portMappings = lib.pipe services [
      (lib.filterAttrs (_: s: (s.vpn or null) == "pia"))
      (lib.mapAttrsToList (_: s: {
        from = s.port;
        to = s.port;
      }))
    ];
  };

  systemd.services.qbittorrent.vpnConfinement = piaConfined;
  systemd.services.sabnzbd.vpnConfinement = piaConfined;
  systemd.services.sonarr.vpnConfinement = piaConfined;
  systemd.services.radarr.vpnConfinement = piaConfined;
  systemd.services.lidarr.vpnConfinement = piaConfined;
  systemd.services.bazarr.vpnConfinement = piaConfined;
  systemd.services.prowlarr.vpnConfinement = piaConfined;
  systemd.services."podman-chaptarr".vpnConfinement = piaConfined;
  systemd.services."podman-buildarr".vpnConfinement = piaConfined;

  systemd.services.pia = {
    after = ["pia-wg-config.service"];
    wants = ["pia-wg-config.service" "pia-escape-route.service"];
  };

  systemd.services.pia-wg-config = {
    description = "Register an ephemeral WireGuard key with PIA and write its wg-quick config";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "pia";
      RuntimeDirectoryMode = "0700";
      ExecStart = lib.getExe pia-wg-config;
    };
  };

  systemd.services.pia-escape-route = {
    description = "Route PIA's own WireGuard endpoint via the bridge instead of through the tunnel itself";
    after = ["pia.service"];
    bindsTo = ["pia.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = lib.getExe pia-escape-route;
    };
  };

  systemd.services.pia-portfwd = {
    description = "Keep PIA's forwarded port bound and pointed at qbittorrent";
    after = ["pia-wg-config.service" "pia-escape-route.service" "qbittorrent.service"];
    wants = ["pia-wg-config.service" "pia-escape-route.service" "qbittorrent.service"];
    wantedBy = ["multi-user.target"];
    vpnConfinement = piaConfined;
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "30s";
      ExecStart = lib.getExe pia-portfwd;
    };
  };

  # /var/www/pages/vpn is where vpn-status.service (below) writes its
  # index.html - the catch-all *.marcel.cool vhost in proxy.nix only creates
  # the /var/www/pages parent, not this subdirectory.
  systemd.tmpfiles.rules = ["d /var/www/pages/vpn 0755 root root -"];

  # https://vpn.marcel.cool - static health page regenerated every minute by
  # a timer. Needs no nginx config: the catch-all ~^*.marcel.cool vhost in
  # proxy.nix serves /var/www/pages/<sub>/index.html, and the *.marcel.cool
  # wildcard DNS + cert already cover the subdomain.
  systemd.services.vpn-status = {
    description = "Generate vpn tunnel status html (pia)";
    after = ["pia.service"];
    wants = ["pia.service"];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      TimeoutStartSec = "30s";
    };
    path = [pkgs.iproute2 pkgs.wireguard-tools pkgs.curl pkgs.jq pkgs.coreutils pkgs.gawk];
    script = ''
      set -euo pipefail
      out=/var/www/pages/vpn
      tmp=$(mktemp "$out/.index.XXXXXX")
      trap 'rm -f "$tmp"' EXIT

      now=$(date +%s)
      gen_epoch=$now
      gen=$(date -u -d "@$now" '+%Y-%m-%d %H:%M:%S UTC')

      esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' <<< "$1"; }
      fmt_age() { printf '%dm %02ds' $(($1 / 60)) $(($1 % 60)); }

      state=DOWN; state_color="#ef4444"; state_msg="netns pia not found"
      hs_age=-1; endpoint="-"; public_key="-"; rows=""
      wg_out="(netns pia not found)"

      if wg_out=$(ip netns exec pia wg show 2>&1); then
        hs=$(ip netns exec pia wg show all latest-handshakes | awk '{if ($NF+0 > s) s = $NF+0} END {print s + 0}')
        hs_age=$(( now - hs ))
        endpoint=$(awk '/endpoint:/{print $2; exit}' <<< "$wg_out")
        public_key=$(awk '/^peer:/{print $2; exit}' <<< "$wg_out")
        if [ "$hs_age" -gt 180 ]; then
          state_msg="handshake ''${hs_age}s old (stale; expected < 180s)"
        else
          exit_ip=$(ip netns exec pia curl -s --max-time 8 'https://api.ipify.org?format=json' | jq -r '.ip // empty' || true)
          if [ -n "$exit_ip" ]; then
            state=UP; state_color="#22c55e"; state_msg="tunnel up, egress reachable"
          else
            state=DEGRADED; state_color="#f59e0b"; state_msg="handshake fresh but egress check failed"
          fi
          server=$(cat /run/pia/gateway_hostname 2>/dev/null || echo "-")
          # forwarded port is the reason pia exists; pia-portfwd keeps it
          # bound in qbit, so read it back out of qbit's own preferences.
          # log in fresh rather than reusing pia-portfwd's cookie - qbit ties
          # sessions to the path they were issued on, and this reaches qbit
          # via the bridge address while pia-portfwd uses loopback.
          qbitUrl="http://${config.vpnNamespaces.pia.namespaceAddress}:${toString services.qbit.port}"
          cookie=$(mktemp)
          curl -sf -m 5 -c "$cookie" -H "Referer: $qbitUrl" \
            --data-urlencode "username=$(cat ${config.sops.secrets."web_user".path})" \
            --data-urlencode "password=$(cat ${config.sops.secrets."web_pass".path})" \
            "$qbitUrl/api/v2/auth/login" >/dev/null 2>&1 || true
          port=$(curl -sf -m 5 -b "$cookie" -H "Referer: $qbitUrl" "$qbitUrl/api/v2/app/preferences" \
            | jq -r '.listen_port // empty' 2>/dev/null) || port=""
          rm -f "$cookie"
          port_disp="''${port:-unavailable (pia-portfwd/qbit not reachable)}"
          rows="<tr><td>exit ip</td><td>$(esc "''${exit_ip:--}")</td></tr><tr><td>pia server</td><td>$(esc "$server")</td></tr><tr><td>forwarded port</td><td>$port_disp</td></tr>"
        fi
      fi

      hs_disp="never"
      [ "$hs_age" -ge 0 ] && hs_disp="$(fmt_age "$hs_age") ago"

      cat > "$tmp" <<EOF
      <!doctype html>
      <html lang="en"><head><meta charset="utf-8">
      <title>vpn status</title>
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <meta http-equiv="refresh" content="60">
      <style>
        body{background:#0d1117;color:#c9d1d9;font:16px/1.5 system-ui,sans-serif;margin:0;display:flex;min-height:100vh;align-items:center;justify-content:center}
        main{padding:2rem;max-width:640px;width:100%}
        h1{font-size:1rem;font-weight:400;color:#8b949e;margin:0 0 1rem}
        .badge{font-size:2.4rem;font-weight:700;padding:.5rem 1.5rem;border-radius:.5rem;display:inline-block;color:#0d1117}
        .msg{color:#8b949e;margin:.75rem 0 1.5rem}
        #stale{display:none;background:#f59e0b;color:#0d1117;padding:.5rem 1rem;border-radius:.4rem;margin-bottom:1.5rem;font-weight:600}
        table{border-collapse:collapse;width:100%}
        td{padding:.3rem 0;border-bottom:1px solid #21262d}
        td:first-child{color:#8b949e;width:11em}
        td:last-child{font-family:ui-monospace,monospace;word-break:break-all}
        pre{background:#161b22;border:1px solid #21262d;border-radius:.4rem;padding:1rem;overflow-x:auto;font-size:.8rem}
        footer{color:#484f58;font-size:.8rem;margin-top:1.5rem}
      </style></head><body><main>
      <h1>pia wireguard · mlab · netns pia</h1>
      <span class="badge" style="background:$state_color">$state</span>
      <p class="msg">$state_msg</p>
      <div id="stale">⚠ page is stale — generator has not run in &gt; 5 min</div>
      <table>$rows
        <tr><td>endpoint</td><td>$(esc "$endpoint")</td></tr>
        <tr><td>last handshake</td><td>$hs_disp</td></tr>
        <tr><td>peer public key</td><td>$(esc "$public_key")</td></tr>
      </table>
      <pre>$(esc "$wg_out")</pre>
      <footer>generated $gen · refreshes every 60 s · data: wg show + egress check from inside the netns</footer>
      <script>const g=$gen_epoch*1000;setTimeout(()=>{if(Date.now()-g>300000){const s=document.getElementById('stale');s.style.display='block';s.textContent='⚠ page is stale — generator has not run in '+Math.round((Date.now()-g)/60000)+' min'}},50)</script>
      </main></body></html>
      EOF
      mv "$tmp" "$out/index.html"
      # mktemp is 0600; nginx needs to read the page
      chmod 644 "$out/index.html"
      trap - EXIT
    '';
  };

  systemd.timers.vpn-status = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "45s";
      OnUnitActiveSec = "60s";
    };
  };
}
