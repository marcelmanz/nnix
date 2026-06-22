{
  config,
  pkgs,
  pkgsStable,
  ...
}: let
  homeDir = config.home.homeDirectory;
in {
  programs.firefox = {
    package = config.lib.nixGL.wrap pkgs.firefox;
  };

  programs.gpg = {
    enable = true;
    package = pkgs.gnupg;
  };

  services.gpg-agent = {
    enable = true;
    pinentry.package = pkgs.pinentry-curses;
    defaultCacheTtl = 3600;
    maxCacheTtl = 28800;
  };

  services.gnome-keyring.enable = true;

  home.packages = with pkgs; [
    (element-desktop.override {commandLineArgs = "--password-store=gnome-libsecret";})
    _1password-cli
    pnpm
    attic-client
    blueman
    # sway # for now we will install it via apt
    # python313Packages.python-lsp-server
    (config.lib.nixGL.wrap _1password-gui)
    (config.lib.nixGL.wrap alacritty)
    (config.lib.nixGL.wrap neovide)
    (config.lib.nixGL.wrap imv)
    (config.lib.nixGL.wrap niri)
    (config.lib.nixGL.wrap freetube)
    (config.lib.nixGL.wrap nautilus)
    (config.lib.nixGL.wrap mermaid-cli)
    (config.lib.nixGL.wrap aonsoku)
    (config.lib.nixGL.wrap localsend)
    (config.lib.nixGL.wrap proton-authenticator)
    (config.lib.nixGL.wrap brave-origin)
  ];

  sops = {
    defaultSopsFile = ../../secrets/work.yaml;
    defaultSopsFormat = "yaml";
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

    secrets.attic_token = {};
    secrets.github_ssh_key = {
      sopsFile = ../../secrets/github.yaml;
      path = "${config.home.homeDirectory}/.ssh/github_ed25519";
    };
  };

  systemd.user.services.attic-watch-store = {
    Unit = {
      Description = "Attic Watch Store (Background Upload to mlab)";
      After = ["network-online.target"];
    };

    Install = {
      WantedBy = ["default.target"];
    };

    Service = {
      ExecStart = pkgs.writeShellScript "attic-watch-wrapper" ''
        TOKEN=$(${pkgs.coreutils}/bin/cat ${config.sops.secrets.attic_token.path})
        ${pkgs.attic-client}/bin/attic login mlab https://cache.marcel.cool "$TOKEN"
        exec ${pkgs.attic-client}/bin/attic watch-store mlab:system
      '';
      Restart = "always";
      RestartSec = "10s";
    };
  };

  nix.package = pkgs.nix;
  nix.settings = {
    trusted-users = ["root" "mmanzanares"];
    experimental-features = ["nix-command" "flakes"];
    substituters = [
      "https://cache.nixos.org"
      "https://cache.marcel.cool/system"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "system:Ve/kZ+DnW135w7Z44yIxH0kOgIXoK6akWv282O2xmWM="
    ];
  };

  home.file = let
    link = config.lib.file.mkOutOfStoreSymlink;
    clonesOwn = "${homeDir}/clones/own";
    dots = "${clonesOwn}/dots";
  in {
    ".config/kanshi/config".source = link "${dots}/.config/kanshi/config-work";
    ".cargo/env".source = link "${dots}/.cargo/env";
    ".cargo/env.fish".source = link "${dots}/.cargo/env.fish";
    ".cargo/env.nu".source = link "${dots}/.cargo/env.nu";
    ".config/hypr/devices/WS0277.conf".source =
      link "${dots}/.config/hypr/devices/WS0277.conf";
    ".mozilla/native-messaging-hosts/passff.json".source = "${pkgs.passff-host}/lib/mozilla/native-messaging-hosts/passff.json";
  };
}
