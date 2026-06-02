{
  description = "NixOS and Home Manager configuration";

  inputs = {
    crane.url = "github:ipetkov/crane";
    mq.url = "github:themarcel/mq";
    musnix.url = "github:musnix/musnix";
    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    my-nixpkgs.url = "github:themarcel/nixpkgs";
    nixpkgsStable.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs2405.url = "github:NixOS/nixpkgs/nixos-24.05";
    nu-alias-converter.url = "github:themarcel/nu-alias-converter";
    nur.url = "github:nix-community/NUR";
    rust-overlay.url = "github:oxalica/rust-overlay";
    nvim.url = "github:themarcel/nvim-lua";
    cliflux.url = "git+https://codeberg.org/themarcel/cliflux?ref=personal";
    dots = {
      url = "github:themarcel/dots";
      flake = false;
    };
    xelabash = {
      url = "github:themarcel/xelabash";
      flake = false;
    };
    foot-fork = {
      url = "git+https://codeberg.org/themarcel/foot?ref=regex-scrollback-search";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zuban.url = "github:themarcel/zuban";
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
      url = "github:themarcel/tmex";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    brave-origin-pr.url = "github:NixOS/nixpkgs?ref=refs/pull/511131/head";
    # pi-undo-redo.url = "path:/home/mmanzanares/clones/forks/pi-undo-redo";
    # hyprland = {
    #   url = "github:hyprwm/Hyprland";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    # hyprland-plugins = {
    #   url = "github:hyprwm/hyprland-plugins";
    #   inputs.nixpkgs.follows = "nixpkgs";
    #   inputs.hyprland.follows = "hyprland";
    # };
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
    rust-overlay,
    brave-origin-pr,
    ...
  } @ inputs: let
    # hyprlandInputs = inputs.hyprland;
    # hyprlandPlugins = inputs."hyprland-plugins";
    system = "x86_64-linux";
    androidSystem = "aarch64-linux";
    username = "marcel";
    hostname = "nixos";
    tmexPkg = tmex.packages.${system}.tmex;
    rust = import ./packages/rust/common.nix {inherit nixpkgs crane rust-overlay;};
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
        permittedInsecurePackages = [
          "qtwebengine-5.15.19"
        ];
      };
      overlays = [
        # hyprlandInputs.overlays.default
        # hyprlandPlugins.overlays.default
        nur.overlays.default
        (import ./overlays/neovim-nightly.nix {inherit inputs;})
        (final: prev: {tmex = tmexPkg;})
        (final: prev: {nuit = nu-alias-converter.packages.${system}.default;})
        (final: prev: {lsv = import ./packages/lsv/package.nix {inherit (rust) craneLib pkgs;};})
        (final: prev: {"audio-select" = import ./packages/audio-select/package.nix {inherit (rust) craneLib pkgs;};})
        (final: prev: {rff = import ./packages/rff/package.nix {inherit (rust) craneLib pkgs;};})
        (final: prev: {
          "pulseaudio-next-output" = import ./packages/pulseaudio-next-output/package.nix {inherit (rust) craneLib pkgs;};
        })
        (final: prev: {"git-commit-search" = import ./packages/git-commit-search/package.nix {inherit (rust) craneLib pkgs;};})
        (final: prev: {haralyzer = import ./packages/haralyzer/package.nix {inherit pkgs;};})
        (final: prev: {discogs2xlsx = import ./packages/discogs2xlsx/package.nix {inherit pkgs;};})
        # (final: prev: { foot = inputs.foot-fork.packages.${system}.default; })
        (final: prev: {zuban = inputs.zuban.packages.${system}.default;})
        # (final: prev: {pi-undo-redo = inputs.pi-undo-redo.packages.${pkgs.system}.default;})
        (final: prev: {cliflux = inputs.cliflux.packages.${system}.default;})
        (final: prev: {"ki-editor" = inputs.ki-editor.packages.${system}.default;})
        (final: prev: {
          protonmail-desktop = inputs.my-nixpkgs.legacyPackages.${system}.protonmail-desktop;
        })
        (final: prev: {
          "brave-origin" =
            (import brave-origin-pr {
              inherit system;
              config.allowUnfree = true;
            })."brave-origin";
        })
        #  force audio & bluetooth to use the stable channel
        # (final: prev: {
        #   pipewire = pkgsStable.pipewire;
        #   wireplumber = pkgsStable.wireplumber;
        #   bluez = pkgsStable.bluez;
        # })
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
    # custom android bootstrap zipball generator
    packages.${system}.android-bootstrap = import ./hosts/android/bootstrap.nix {
      inherit pkgs nix-on-droid system;
      targetSystem = "aarch64-linux";
      sshKeyPath = ./hosts/android/ssh.pub;
      flakeSource = ./.;
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
