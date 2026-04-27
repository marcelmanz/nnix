{
  _config,
  _pkgs,
  services,
  ...
}: {
  virtualisation.oci-containers = {
    backend = "podman";
    containers.hyperpipe = {
      image = "codeberg.org/hyperpipe/hyperpipe:latest";
      ports = ["127.0.0.1:${toString services.ytmusic.port}:3000"];
      environment = {
        HYP_API = services.pipedapi.href;
        PIPED_API = services.pipedapi.href;
      };
    };
  };
}
