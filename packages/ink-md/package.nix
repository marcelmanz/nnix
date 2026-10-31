{
  craneLib,
  pkgs,
}:
craneLib.buildPackage {
  pname = "ink-md";
  version = "0.13.0";
  src = pkgs.fetchFromGitHub {
    owner = "marcelmanz";
    repo = "ink";
    rev = "29cc640f2fb072707bcae6d628718a8f41d2340d";
    sha256 = "sha256-/ImdciTisBVhzpBL8mP71OIQOzPR7iQaGidHTp+UKWU=";
  };
  cargoVendorHash = pkgs.lib.fakeHash;
}
