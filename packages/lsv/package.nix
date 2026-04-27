{
  craneLib,
  pkgs,
}:
craneLib.buildPackage {
  pname = "lsv";
  version = "0.1.11";
  src = pkgs.fetchCrate {
    pname = "lsv";
    version = "0.1.11";
    sha256 = "sha256-IJ0ug8uU/yVGd99Lvp5kCRwV6WHDC/zXg5zO0KT6Lek=";
  };
  cargoVendorHash = pkgs.lib.fakeHash;
}
