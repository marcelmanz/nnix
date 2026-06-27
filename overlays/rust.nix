{ pkgs }:
let
  # Build one rust crate using crane
  mkRustCrate = name: 
    pkgs.crane.buildPackage {
      pname = name;
      version = {
        lsv = "0.1.11";
        audio-select = "unstable-20250320";
        rff = "unstable-2025-11-03";
        git-commit-search = "unstable-20250313";
        "pulseaudio-next-output" = "unstable-2025-09-04";
      }."${name}";
      cargoVendorHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      nativeBuildInputs = with pkgs; [pkg-config] ++ (if name == "audio-select" then [wrapGAppsHook3] else []);
      buildInputs = with pkgs; let
        base = (if name == "git-commit-search" || name == "rff" then [openssl] else
          (if name == "pulseaudio-next-output" then [pulseaudio] else []
        );
        extra = if name == "audio-select" then [atk cairo gdk-pixbuf glib gtk3 libpulseaudio pango] else [];
      in base ++ extra;
      src = {
        lsv = pkgs.fetchCrate {
          pname = "lsv";
          version = {
            lsv = "0.1.11";
            audio-select = "unstable-20250320";
            rff = "unstable-2025-11-03";
            git-commit-search = "unstable-20250313";
            "pulseaudio-next-output" = "unstable-2025-09-04";
          }."${name}";
          sha256 = "sha256-IJ0ug8uU/yVGd99Lvp5kCRwV6WHDC/zXg5zO0KT6Lek=";
        };
        "audio-select" = pkgs.fetchgit {
          url = "https://github.com/sudosteve/audio-select.git";
          rev = "ecbd5e8a5ad073e79c5a7ffe017d9a73de3dcfa4";
          sha256 = "sha256-X3rfil0dAVvEHgRcL4BGdqH5qLo/VS74UB5fEH6m0jE=";
        };
        rff = pkgs.fetchgit {
          url = "https://github.com/crabbylab/rff.git";
          rev = "d7f6a909f26439ef1c44d4a1e1241353a26c3d65";
          sha256 = "sha256-zXqXCL0pswtGnoQwE4Kmt8LSI4LIuMny3T0+o3+bmtU=";
        };
        "git-commit-search" = pkgs.fetchgit {
          url = "https://github.com/marcelmanz/git-commit-search";
          rev = "dc626596af8b1351eb5a062d8d4b7c065e6d8f1c";
          sha256 = "sha256-hRuObffjVo4ncnMZPRYz2hHB8E9nLggRNWkoHL7+V6I=";
        };
        "pulseaudio-next-output" = pkgs.fetchgit {
          url = "https://github.com/murlakatamenka/pulseaudio-next-output";
          rev = "e46ea275e17ec7e00edd1c9627f00c4b7134b012";
          sha256 = "sha256-GuZCop5hUWeBqEYQB3O+MnQVg3uve3pC4ZjLejDflUc=";
        };
      }."${name}";
    };
in
final: prev:
  pkgs.lib.genAttrs ["lsv" "audio-select" "rff" "pulseaudio-next-output" "git-commit-search"] mkRustCrate