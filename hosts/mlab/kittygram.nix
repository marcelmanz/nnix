{ ... }:

{
  # Proxied via proxy.nix (services.insta -> insta.marcel.cool).
  virtualisation.oci-containers.containers.kittygram = {
    image = "git.rauhala.info/rytovuori/kittygram:latest";
    ports = [ "127.0.0.1:3022:3000" ];
  };
}
