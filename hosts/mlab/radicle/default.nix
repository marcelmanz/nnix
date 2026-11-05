{
  config,
  lib,
  services,
  ...
}: let
  meilisearchUrl = "http://127.0.0.1:${toString config.services.meilisearch.listenPort}";
in {
  sops.secrets."radicle_node_key" = {};
  sops.secrets."meilisearch_master_key" = {};
  sops.templates."radicle-search.env".content = ''
    RADICLE_SEARCH_KEY=${config.sops.placeholder.meilisearch_master_key}
    RADICLE_SEARCH_MEILI_KEY=${config.sops.placeholder.meilisearch_master_key}
  '';

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

  services.meilisearch = {
    enable = true;
    listenAddress = "127.0.0.1";
    masterKeyFile = config.sops.secrets.meilisearch_master_key.path;
  };

  systemd.services.radicle-node.serviceConfig.MemoryMax = "2G";
  systemd.services.radicle-httpd.environment.RADICLE_SEARCH_URL = meilisearchUrl;
  systemd.services.radicle-httpd.serviceConfig = {
    MemoryMax = "2G";
    EnvironmentFile = config.sops.templates."radicle-search.env".path;
    BindReadOnlyPaths = [
      "/var/lib/radicle/storage"
      "/var/lib/radicle/cobs"
      "/var/lib/radicle/node/policies.db"
    ];
  };

  systemd.services.radicle-search = let
    httpd = config.systemd.services.radicle-httpd;
  in {
    description = "Radicle search indexer";
    inherit (httpd) path confinement;
    environment = builtins.removeAttrs httpd.environment ["PATH"] // {RADICLE_SEARCH_MEILI_URL = meilisearchUrl;};
    after = ["radicle-node.service" "meilisearch.service"];
    wants = ["radicle-node.service" "meilisearch.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig =
      httpd.serviceConfig
      // {
        ExecStart = lib.getExe' config.services.radicle.httpd.package "radicle-search";
        SocketBindAllow = [];
        MemoryMax = "1G";
      };
  };

  networking.firewall.extraCommands = ''
    radicle_output_rule() {
      local cmd=$1
      shift
      $cmd -C OUTPUT -m owner --uid-owner radicle "$@" 2>/dev/null \
        || $cmd -A OUTPUT -m owner --uid-owner radicle "$@"
    }
    iptables -C OUTPUT -m owner --uid-owner radicle -o lo -p tcp --dport ${toString config.services.meilisearch.listenPort} -d 127.0.0.1 -j ACCEPT 2>/dev/null \
      || iptables -I OUTPUT 1 -m owner --uid-owner radicle -o lo -p tcp --dport ${toString config.services.meilisearch.listenPort} -d 127.0.0.1 -j ACCEPT
    radicle_output_rule iptables -o lo -p udp --dport 53 -d 127.0.0.53 -j ACCEPT
    radicle_output_rule iptables -o lo -p tcp --dport 53 -d 127.0.0.53 -j ACCEPT
    radicle_output_rule iptables -o lo -m conntrack --ctstate NEW -j REJECT
    radicle_output_rule iptables -d 10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.0.0/16 -m conntrack --ctstate NEW -j REJECT
    radicle_output_rule ip6tables -o lo -m conntrack --ctstate NEW -j REJECT
    radicle_output_rule ip6tables -d fc00::/7,fe80::/10 -m conntrack --ctstate NEW -j REJECT
  '';
}
