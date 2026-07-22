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
    nu-alias-converter.url = "github:marcelmanz/nu-alias-converter";
    nur.url = "github:nix-community/NUR";
    # rust-overlay = {
    #   url = "github:oxalica/rust-overlay";
    #   inputs.crane.follows = "crane";
    # };
    nvim.url = "github:marcelmanz/nvim-lua";
    cliflux.url = "git+https://codeberg.org/marcelmanz/cliflux?ref=personal";
    dots = {
      url = "github:marcelmanz/dots";
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
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    brave-origin-pr.url = "github:NixOS/nixpkgs?ref=refs/pull/513143/head";
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgsStable,
    nixGL,
    home-manager,
    nix-on-droid,
    tmex,
    neovim-nightly-overlay,
    nu-alias-converter,
    nur,
    my-nixpkgs,
    disko,
    nixpkgs2405,
    crane,
    # rust-overlay,
    brave-origin-pr,
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
        ];
      };
      overlays = [
        nur.overlays.default
        (import ./overlays/neovim-nightly.nix {inherit inputs;})
        (final: prev: {tmex = tmexPkg;})
        (final: prev: {nuit = nu-alias-converter.packages.${system}.default;})
        (import ./overlays/rust.nix {inherit pkgs crane;})
        (final: prev: {haralyzer = import ./packages/haralyzer/package.nix {inherit pkgs;};})
        (final: prev: {discogs2xlsx = import ./packages/discogs2xlsx/package.nix {inherit pkgs;};})
        (final: prev: {zuban = inputs.zuban.packages.${system}.default;})
        (final: prev: {cliflux = inputs.cliflux.packages.${system}.default;})
        (final: prev: {
          protonmail-desktop = inputs.my-nixpkgs.legacyPackages.${system}.protonmail-desktop;
        })
        (final: prev: {
          "brave-origin" =
            (import brave-origin-pr {
              inherit system;
              config.allowUnfree = true;
            })."brave-origin-nightly";
        })
      ];
    };
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
      # custom android bootstrap zipball generator
      android-bootstrap = import ./hosts/android/bootstrap.nix {
        inherit pkgs nix-on-droid system;
        targetSystem = "aarch64-linux";
        sshKeyPath = ./hosts/android/ssh.pub;
        flakeSource = ./.;
      };
      lsv = pkgs.lsv;
      "audio-select" = pkgs."audio-select";
      rff = pkgs.rff;
      "pulseaudio-next-output" = pkgs."pulseaudio-next-output";
      "git-commit-search" = pkgs."git-commit-search";
      # Commented out due to cycles
      # Commented out due to cycles
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
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            users.${username} = import ./hosts/home/default.nix;
            extraSpecialArgs = {inherit inputs pkgsStable nixGL;};
          };
        }
      ];
    };

    nixosConfigurations.vps = nixpkgs.lib.nixosSystem {
      inherit system pkgs;
      specialArgs = {inherit inputs;};
      modules = [
        disko.nixosModules.disko
        ./hosts/vps/default.nix
      ];
    };

    nixosConfigurations.mlab = nixpkgs.lib.nixosSystem {
      inherit system pkgs;
      specialArgs = {inherit inputs;};
      modules = [
        inputs.sops-nix.nixosModules.sops
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
