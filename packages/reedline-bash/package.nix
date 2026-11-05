{
  craneLib,
  pkgs,
}:
craneLib.buildPackage {
  pname = "reedline-bash";
  version = "unstable-2026-11-02";
  src = pkgs.fetchgit {
    # TODO: back to upstream once https://github.com/maxomatic458/reedline-bash/pull/3 is merged
    url = "https://github.com/marcelmanz/reedline-bash";
    rev = "758086417119de0944a0c97e9d0153e39b8cca77";
    fetchSubmodules = false;
    sha256 = "sha256-VqWkEoYf9YQHy2BkXAnPzvbYiGwl6Nkj0SGbDGMciqM=";
  };
  cargoVendorHash = pkgs.lib.fakeHash;
}
