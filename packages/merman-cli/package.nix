{
  craneLib,
  pkgs,
}:
craneLib.buildPackage {
  pname = "merman-cli";
  version = "0.10.0";
  src = pkgs.fetchzip {
    url = "https://crates.io/api/v1/crates/merman-cli/0.10.0/download";
    extension = "tar.gz";
    sha256 = "sha256-lFGG8213VhMudH6htajxljArcD6SqjiAtnFitSQ6BtM=";
  };
}
