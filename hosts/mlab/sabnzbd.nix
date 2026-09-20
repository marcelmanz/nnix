{
  _config,
  lib,
  services,
  ...
}: {
  sops.secrets."sabnzbd_api" = {};

  systemd.tmpfiles.rules = [
    "d /var/lib/sabnzbd 0775 sabnzbd media -"
  ];

  services.sabnzbd = {
    enable = true;
    openFirewall = false; # nginx fronts this
    configFile = null;
    group = "media";
    settings = {
      misc = {
        host_whitelist = "sabnzbd.marcel.cool, mlab, 127.0.0.1";
        # web UI bind address. sabnzbd is NOT vpn-confined (see vpn.nix), so
        # nginx and homepage reach it on host loopback. It still binds 0.0.0.0
        # because the confined *arr apps reach it over the pia bridge address;
        # the firewall only accepts that port from the bridge, not the LAN.
        # (there is no top-level "server" option - that key silently wrote a
        # dead [server] ini section instead of ever setting this.)
        host = "0.0.0.0";
        port = services.sabnzbd.port;
      };
      # Credentials stay in the runtime ini: the merge is recursive and runs
      # nix-last, so these keys win while username/password survive untouched.
      # Measured off-tunnel (see vpn.nix), 15s per run over alt.binaries.boneless:
      #   eweka    20 conns 166 MB/s | 40 conns 332 MB/s | 50 conns 347 MB/s
      #   giganews 20 conns 9.5 MB/s | 40 conns  21 MB/s
      # so eweka at its 50-connection account cap saturates the 2.8 Gbit line
      # and giganews is provider-limited whatever we do - hence backup only.
      servers = {
        "news.eweka.nl" = {
          name = "news.eweka.nl";
          displayname = "Eweka";
          host = "news.eweka.nl";
          # 563/TLS, not 119/plaintext: same throughput, and the tunnel was
          # the only reason plaintext ever looked faster.
          port = 563;
          ssl = true;
          connections = 50;
          priority = 0;
          # the module's null default renders as the literal "None"; SAB wants
          # an empty string for "no expiry", which is what it already has.
          expire_date = "";
        };
        "news.giganews.com" = {
          name = "news.giganews.com";
          displayname = "Giganews";
          host = "news.giganews.com";
          port = 443;
          ssl = true;
          # account allows 100; 50 is enough for a fill server that only ever
          # sees what eweka is missing.
          connections = 50;
          priority = 12;
          expire_date = "";
        };
      };
    };
    allowConfigWrite = true;
  };

  users.users.sabnzbd = {
    extraGroups = ["media"];
  };

  systemd.services.sabnzbd.serviceConfig = {
    ReadWritePaths = ["/var/lib/media"];
    UMask = lib.mkForce "0002";
  };
}
