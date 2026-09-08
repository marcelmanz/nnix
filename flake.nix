{
  description = "NixOS and Home Manager configuration";

  inputs = {
    crane.url = "github:ipetkov/crane";
    musnix.url = "github:musnix/musnix";
    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    my-nixpkgs.url = "github:marcelmanz/nixpkgs";
    nixpkgsStable.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs2405.url = "github:NixOS/nixpkgs/nixos-24.05";
    openlogi.url = "github:AprilNEA/OpenLogi";
    nu-alias-converter.url = "github:marcelmanz/nu-alias-converter";
    nur.url = "github:nix-community/NUR";
    # rust-overlay = {
    #   url = "github:oxalica/rust-overlay";
    #   inputs.crane.follows = "crane";
    # };
    nvim.url = "github:marcelmanz/nvim-lua";
    psysonic.url = "github:Psysonic/psysonic?ref=release";
    cliflux.url = "git+https://codeberg.org/marcelmanz/cliflux?ref=personal";
    brave-origin-channels = {
      url = "git+https://codeberg.org/marcelmanz/brave-origin-channels";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dots = {
      url = "github:marcelmanz/dots";
      flake = false;
    };
    myna = {
      url = "github:sayyadirfanali/Myna";
      flake = false;
    };
    xelabash = {
      url = "github:marcelmanz/xelabash";
      flake = false;
    };
    zuban.url = "github:marcelmanz/zuban";
    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixGL = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    tmex = {
      url = "github:marcelmanz/tmex";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pir = {
      url = "git+https://codeberg.org/marcelmanz/pir";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    vpn-confinement.url = "github:Maroka-chan/VPN-Confinement";
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgsStable,
    nixGL,
    home-manager,
    nix-on-droid,
    tmex,
    pir,
    neovim-nightly-overlay,
    nu-alias-converter,
    nur,
    my-nixpkgs,
    nixpkgs2405,
    crane,
    # rust-overlay,
    ...
  } @ inputs: let
    system = "x86_64-linux";
    androidSystem = "aarch64-linux";
    username = "marcel";
    hostname = "nixos";
    tmexPkg = tmex.packages.${system}.tmex;
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
        permittedInsecurePackages = [
          "qtwebengine-5.15.19"
          "pnpm-9.15.9"
          "olm-3.2.16" # mautrix-whatsapp links libolm (deprecated, CVE-2024-45191/2/3) for optional E2E
        ];
      };
      overlays = [
        nur.overlays.default
        (import ./overlays/neovim-nightly.nix {inherit inputs;})
        (import ./overlays/mautrix-whatsapp.nix)
        (import ./overlays/hyprland-glaze-fix.nix)
        (import ./overlays/font-manager-vala-fix.nix)
        (import ./overlays/myna-font.nix {inherit inputs;})
        (final: prev: {tmex = tmexPkg;})
        pir.overlays.default
        (import ./overlays/pi-jiti-cache.nix)
        (final: prev: {nuit = nu-alias-converter.packages.${system}.default;})
        (import ./overlays/rust.nix {inherit pkgs crane;})
        (final: prev: {haralyzer = import ./packages/haralyzer/package.nix {inherit pkgs;};})
        (final: prev: {discogs2xlsx = import ./packages/discogs2xlsx/package.nix {inherit pkgs;};})
        (final: prev: {"nitter-session" = import ./packages/nitter-session/package.nix {inherit pkgs;};})
        (final: prev: {zuban = inputs.zuban.packages.${system}.default;})
        (final: prev: {cliflux = inputs.cliflux.packages.${system}.default;})
        (final: prev: {
          protonmail-desktop = inputs.my-nixpkgs.legacyPackages.${system}.protonmail-desktop;
        })
        (final: prev: {"brave-origin" = inputs.brave-origin-channels.packages.${system}.nightly;})
        (final: prev: {psysonic = inputs.psysonic.packages.${system}.psysonic;})
        (final: prev: {
          offtiktok = pkgs.callPackage ./packages/offtiktok/frontend.nix {};
          offtiktokapi = pkgs.callPackage ./packages/offtiktok/backend.nix {};
        })
      ];
    };
    pkgs_rust = pkgs;
    pkgsAndroid = import nixpkgs2405 {
      system = androidSystem;
      config.allowUnfree = true;
    };
    pkgsStable = import nixpkgsStable {
      inherit system;
      config.allowUnfree = true;
    };
  in {
    packages.${system} = {
      lsv = pkgs.lsv;
      "audio-select" = pkgs."audio-select";
      rff = pkgs.rff;
      "pulseaudio-next-output" = pkgs."pulseaudio-next-output";
      "git-commit-search" = pkgs."git-commit-search";
      "nitter-session" = pkgs."nitter-session";
      mautrix-whatsapp = pkgs.mautrix-whatsapp;
      # Commented out due to cycles
      # Commented out due to cycles
      ruff = pkgs.ruff;
      oxfmt = pkgs.oxfmt;
    };
    devShells.${system}.default = pkgs.mkShell {
      packages = with pkgs; [
        git
        nix-prefetch
      ];
      shellHook = ''
        echo "🐚  Dev shell for ${username} on ${system} ready!"
        export EDITOR=nvim
      '';
    };

    nixosConfigurations.${hostname} = nixpkgs.lib.nixosSystem {
      inherit system pkgs;
      specialArgs = {inherit inputs pkgsStable username;};
      modules = [
        ./nixos/configuration.nix
        ./nixos/hardware-configuration.nix
        inputs.musnix.nixosModules.musnix
        inputs.sops-nix.nixosModules.sops
        home-manager.nixosModules.home-manager
        inputs.openlogi.nixosModules.default
        {
          programs.openlogi.enable = true;
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            users.${username} = import ./hosts/home/default.nix;
            extraSpecialArgs = {inherit inputs pkgsStable nixGL;};
          };
        }
      ];
    };

    nixosConfigurations.mlab = nixpkgs.lib.nixosSystem {
      inherit system pkgs;
      specialArgs = {inherit inputs;};
      modules = [
        inputs.sops-nix.nixosModules.sops
        inputs.openlogi.nixosModules.default
        inputs.vpn-confinement.nixosModules.default
        {
          programs.openlogi.enable = true;
        }
        ./hosts/mlab/default.nix
      ];
    };

    homeConfigurations = {
      work = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {inherit inputs pkgsStable nixGL;};
        modules = [
          inputs.sops-nix.homeManagerModules.sops
          ./home/gui.nix
          ./home/terminal.nix
          ./hosts/work/default.nix
          (
            {
              config,
              pkgs,
              nixGL,
              ...
            }: {
              home.username = "mmanzanares";
              home.homeDirectory = "/home/mmanzanares";
              targets.genericLinux.enable = true;

              targets.genericLinux.nixGL = {
                packages = nixGL.packages;
                defaultWrapper = "mesa";
              };
            }
          )
        ];
      };
    };

    nixOnDroidConfigurations.default = nix-on-droid.lib.nixOnDroidConfiguration {
      pkgs = pkgsAndroid;
      extraSpecialArgs = {inherit inputs;};
      modules = [
        ./hosts/android/default.nix
      ];
    };
  };
}
