{
  craneLib,
  pkgs,
}: let
  rev = "dc626596af8b1351eb5a062d8d4b7c065e6d8f1c";
in
  craneLib.buildPackage {
    pname = "git-commit-search";
    version = "unstable-${builtins.substring 0 7 rev}";
    src = pkgs.fetchgit {
      url = "https://github.com/themarcel/git-commit-search";
      inherit rev;
      sha256 = "sha256-hRuObffjVo4ncnMZPRYz2hHB8E9nLggRNWkoHL7+V6I=";
    };
    cargoVendorHash = pkgs.lib.fakeHash;
    nativeBuildInputs = with pkgs; [pkg-config];
    buildInputs = with pkgs; [openssl];
  }
