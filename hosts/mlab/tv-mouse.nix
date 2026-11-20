{pkgs, ...}: let
  port = 8125;
  python = pkgs.python3.withPackages (p: [p.dbus-fast p.websockets]);
in {
  # the classic HID host plugin holds PSM 17/19, which tv-mouse needs to act as a mouse
  hardware.bluetooth.disabledPlugins = ["input"];

  systemd.services.tv-mouse = {
    description = "Bluetooth mouse for the Xiaomi TV box, driven from ha.marcel.cool";
    wantedBy = ["multi-user.target"];
    after = ["bluetooth.service"];
    bindsTo = ["bluetooth.service"];
    environment.TV_MOUSE_PORT = toString port;
    serviceConfig = {
      # bluetoothd ignores Class from main.conf; peripheral/pointing so Android TV lists it as an accessory
      ExecStartPre = "+${pkgs.bluez}/bin/btmgmt --index 0 class 5 128";
      ExecStart = "${python}/bin/python3 ${./tv-mouse.py}";
      Restart = "always";
      RestartSec = 5;
      StateDirectory = "tv-mouse";
      CapabilityBoundingSet = ["CAP_NET_BIND_SERVICE"];
      AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      RestrictAddressFamilies = ["AF_BLUETOOTH" "AF_UNIX" "AF_INET" "AF_INET6"];
    };
  };

  services.nginx.virtualHosts."ha.marcel.cool".locations."/tv-mouse/" = {
    proxyPass = "http://127.0.0.1:${toString port}/";
    proxyWebsockets = true;
    extraConfig = ''
      allow 127.0.0.1;
      allow 192.168.1.0/24;
      include /var/lib/lan-ipv6-prefix/nginx-allow*.conf;
      deny all;
      proxy_read_timeout 1h;
    '';
  };
}
