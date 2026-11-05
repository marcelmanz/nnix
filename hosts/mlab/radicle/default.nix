{
  config,
  services,
  ...
}: {
  sops.secrets."radicle_node_key" = {};

  services.radicle = {
    enable = true;
    privateKey = config.sops.secrets.radicle_node_key.path;
    publicKey = ./radicle.pub;
    node.openFirewall = true;
    settings = {
      node = {
        alias = "mlab";
        externalAddresses = ["ssh.marcel.cool:${toString config.services.radicle.node.listenPort}"];
        seedingPolicy.default = "block";
        connect = [
          "z6MkrLMMsiPWUcNPHcRajuMi9mDfYckSoJyPwwnknocNYPm7@iris.radicle.network:8776"
          "z6Mkmqogy2qEM2ummccUthFEaaHvyYmYBYh3dbe9W4ebScxo@rosa.radicle.network:8776"
        ];
      };
    };
    httpd = {
      enable = true;
      listenPort = services.radicle.port;
    };
  };

  systemd.services.radicle-node.serviceConfig.MemoryMax = "2G";
  systemd.services.radicle-httpd.serviceConfig = {
    MemoryMax = "2G";
    ReadOnlyPaths = [
      "/var/lib/radicle/storage"
      "/var/lib/radicle/cobs"
      "/var/lib/radicle/node/policies.db"
    ];
  };

  networking.firewall.extraCommands = ''
    radicle_output_rule() {
      local cmd=$1
      shift
      $cmd -C OUTPUT -m owner --uid-owner radicle "$@" 2>/dev/null \
        || $cmd -A OUTPUT -m owner --uid-owner radicle "$@"
    }
    radicle_output_rule iptables -o lo -p udp --dport 53 -d 127.0.0.53 -j ACCEPT
    radicle_output_rule iptables -o lo -p tcp --dport 53 -d 127.0.0.53 -j ACCEPT
    radicle_output_rule iptables -o lo -m conntrack --ctstate NEW -j REJECT
    radicle_output_rule iptables -d 10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.0.0/16 -m conntrack --ctstate NEW -j REJECT
    radicle_output_rule ip6tables -o lo -m conntrack --ctstate NEW -j REJECT
    radicle_output_rule ip6tables -d fc00::/7,fe80::/10 -m conntrack --ctstate NEW -j REJECT
  '';
}
