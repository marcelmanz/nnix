{
  craneLib,
  pkgs,
}:
craneLib.buildPackage {
  pname = "reedline-bash";
  version = "";
  src = pkgs.fetchgit {
    url = "https://github.com/maxomatic458/reedline-bash";
    rev = "d7f6a909f26439ef1c44d4a1e1241353a26c3d65";
    sha256 = "sha256-zXqXCL0pswtGnoQwE4Kmt8LSI4LIuMny3T0+o3+bmtU=";
  };
  cargoVendorHash = pkgs.lib.fakeHash;
}
