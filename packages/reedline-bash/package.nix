{
  craneLib,
  pkgs,
}:
craneLib.buildPackage {
  pname = "reedline-bash";
  version = "unstable-2026-09-30";
  src = pkgs.fetchgit {
    url = "https://github.com/maxomatic458/reedline-bash";
    rev = "47cf61f14e97bfd1c4893ff1ec0151fe8b18d809";
    fetchSubmodules = false;
    sha256 = "sha256-6XLzHU/A1uUv1pBvwxy08y/ctYE/Velt28BG/EdYaIo=";
  };
  cargoVendorHash = pkgs.lib.fakeHash;
}
