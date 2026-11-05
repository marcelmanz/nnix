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
}
