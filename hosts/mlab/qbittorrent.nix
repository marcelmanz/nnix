{
  config,
  lib,
  services,
  ...
}: {
  # The live config is /var/lib/qBittorrent/qBittorrent/config/qBittorrent.conf
  # (the service runs with --profile=/var/lib/qBittorrent). qBittorrent rewrites
  # the whole file on exit, so it can't be nix-managed wholesale - but the WebUI
  # password IS declarative: preStart injects the sops salt+hash into the conf
  # while the service is down. Other settings: edit in the WebUI, they persist.
  # Rotate: ~/scripts/qbit-pass.sh 'newpass' -> paste into secrets/mlab.yaml -> make mlab

  sops.secrets."qbit_password_salt" = {
    owner = "qbittorrent";
    restartUnits = ["qbittorrent.service"];
  };
  sops.secrets."qbit_password_hash" = {
    owner = "qbittorrent";
    restartUnits = ["qbittorrent.service"];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/qbittorrent 0775 qbittorrent media -"
    "d /var/lib/qbittorrent/.config/qBittorrent 0750 qbittorrent qbittorrent -"
  ];

  services.qbittorrent = {
    enable = true;
    openFirewall = false; # nginx fronts this
    webuiPort = services.qbit.port;
  };

  users.users.qbittorrent.extraGroups = ["media"];

  systemd.services.qbittorrent = {
    serviceConfig = {
      ReadWritePaths = ["/var/lib/media"];
      UMask = lib.mkForce "0002";
    };
    preStart = ''
      conf=/var/lib/qBittorrent/qBittorrent/config/qBittorrent.conf
      # runs as the qbittorrent user, which owns the conf; '.' matches the backslash
      if [ -f "$conf" ] && grep -q "^WebUI.Password_PBKDF2=" "$conf"; then
        sed -i "s|^\(WebUI.Password_PBKDF2=\).*|\1\"@ByteArray($(cat ${config.sops.secrets."qbit_password_salt".path}):$(cat ${config.sops.secrets."qbit_password_hash".path}))\"|" "$conf"
      else
        echo "qbittorrent preStart: $conf or its Password_PBKDF2 line missing; start once to create it" >&2
      fi
      # trust the nginx proxy so bans/real IPs work; without this qbit bans the
      # proxy's source IP after failed logins = whole world locked out for
      # BanDuration. qbit is vpn-confined (vpn.nix), so nginx reaches it
      # via the netns bridge address, not loopback - trust that address instead.
      grep -q "^WebUI.ReverseProxySupportEnabled=" "$conf" || \
        sed -i "/^\[Preferences\]/a WebUI\\\\ReverseProxySupportEnabled=true" "$conf"
      if grep -q "^WebUI.TrustedReverseProxiesList=" "$conf"; then
        sed -i "s|^\(WebUI.TrustedReverseProxiesList=\).*|\1${config.vpnNamespaces.pia.bridgeAddress}|" "$conf"
      else
        sed -i "/^\[Preferences\]/a WebUI\\\\TrustedReverseProxiesList=${config.vpnNamespaces.pia.bridgeAddress}" "$conf"
      fi
      # bind all interfaces, not just loopback - nginx and anything else
      # outside this netns reaches qbit via the bridge address, not 127.0.0.1
      if grep -q "^WebUI.Address=" "$conf"; then
        sed -i "s|^\(WebUI.Address=\).*|\10.0.0.0|" "$conf"
      else
        sed -i "/^\[Preferences\]/a WebUI\\\\Address=0.0.0.0" "$conf"
      fi
      # BT listen socket must bind to "any interface" - a leftover
      # Session\Interface(Name|Address) pinned to the host's real NIC
      # (enp1s0) doesn't exist inside the pia netns, so the listen port never
      # actually opens and qbit is unreachable for peers/trackers even though
      # pia-portfwd reports a bound port.
      sed -i "s|^Session\\\\Interface=.*|Session\\\\Interface=|" "$conf"
      sed -i "s|^Session\\\\InterfaceAddress=.*|Session\\\\InterfaceAddress=|" "$conf"
      sed -i "s|^Session\\\\InterfaceName=.*|Session\\\\InterfaceName=|" "$conf"
    '';
  };
}
