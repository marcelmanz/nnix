{
  description = "git-commit-search via crane (git)";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.crane.url = "github:ipetkov/crane";
  inputs.rust-overlay.url = "github:oxalica/rust-overlay";

  outputs = {
    self,
    nixpkgs,
    crane,
    rust-overlay,
  }: let
    rust = import ../rust/common.nix {inherit nixpkgs crane rust-overlay;};
    system = "x86_64-linux";
  in {
    packages.${system} = let
      rev = "dc626596af8b1351eb5a062d8d4b7c065e6d8f1c";
      gitCommitSearch = rust.craneLib.buildPackage {
        pname = "git-commit-search";
        version = "unstable-${builtins.substring 0 7 rev}";
        src = rust.pkgs.fetchgit {
          url = "https://github.com/marcelmanz/git-commit-search";
          inherit rev;
          sha256 = "sha256-hRuObffjVo4ncnMZPRYz2hHB8E9nLggRNWkoHL7+V6I=";
        };
        cargoVendorHash = rust.pkgs.lib.fakeHash;
        nativeBuildInputs = with rust.pkgs; [pkg-config];
        buildInputs = with rust.pkgs; [openssl];
      };
    in {
      inherit gitCommitSearch;
      default = gitCommitSearch;
    };
  };
}
