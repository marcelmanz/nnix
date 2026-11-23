{pkgs, ...}: let
  port = 6666;
in {
  networking.firewall.interfaces.enp1s0.allowedUDPPorts = [port];

  # Read with: journalctl -u laptop-netconsole -f
  systemd.services.laptop-netconsole = {
    description = "Kernel log of the laptop, received over netconsole";
    wantedBy = ["multi-user.target"];
    after = ["network.target"];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat -u UDP-RECV:${toString port},range=192.168.1.0/24 STDOUT";
      Restart = "always";
      DynamicUser = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = ["AF_INET"];
    };
  };
}
