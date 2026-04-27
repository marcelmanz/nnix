{
  craneLib,
  pkgs,
}: let
  rev = "ecbd5e8a5ad073e79c5a7ffe017d9a73de3dcfa4";
in
  craneLib.buildPackage {
    pname = "audio-select";
    version = "unstable-${builtins.substring 0 7 rev}";
    src = pkgs.fetchgit {
      url = "https://github.com/sudosteve/audio-select.git";
      inherit rev;
      sha256 = "sha256-X3rfil0dAVvEHgRcL4BGdqH5qLo/VS74UB5fEH6m0jE=";
    };
    cargoVendorHash = pkgs.lib.fakeHash;
    nativeBuildInputs = with pkgs; [pkg-config wrapGAppsHook3];
    buildInputs = with pkgs; [atk cairo gdk-pixbuf glib gtk3 libpulseaudio pango];
  }
