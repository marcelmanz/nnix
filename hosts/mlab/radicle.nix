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
      };
    };
    httpd = {
      enable = true;
      listenPort = services.radicle.port;
    };
  };
}
