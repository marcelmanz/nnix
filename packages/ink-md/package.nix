{
  craneLib,
  pkgs,
}:
craneLib.buildPackage {
  pname = "ink-md";
  version = "0.13.0";
  src = pkgs.fetchCrate {
    pname = "ink-md";
    version = "0.13.0";
    sha256 = "sha256-rQfRYonXIYib8bCoN8EZxb7UrW/HBPmvI2qpsh/vT3U=";
  };
  cargoVendorHash = pkgs.lib.fakeHash;
}
