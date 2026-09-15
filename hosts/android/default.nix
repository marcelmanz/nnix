{
  _config,
  pkgs,
  inputs,
  ...
}: let
  stateVersion = "24.05";
  sshKey = builtins.readFile ../android/ssh.pub;
in {
  system.stateVersion = stateVersion;

  # critical: prevents android from killing ssh when the screen is off
  android-integration.termux-wake-lock.enable = true;

  environment.packages = with pkgs; [
    openssh
    git
    vim
    fish
    inetutils
    iproute2
    mosh
    atuin
    direnv
    zoxide
    eza
    carapace
    procps
    bat
    rsync
    gawk
  ];

  environment.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
    OPENSSL_DIR = "${pkgs.openssl.out}";
    OPENSSL_LIB_DIR = "${pkgs.openssl.out}/lib";
    OPENSSL_INCLUDE_DIR = "${pkgs.openssl.dev}/include";
  };

  nix.extraOptions = ''
    substituters = https://cache.nixos.org https://cache.marcel.cool/system
    trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= system:Ve/kZ+DnW135w7Z44yIxH0kOgIXoK6akWv282O2xmWM=
  '';

  home-manager = {
    backupFileExtension = "hm-bak";
    useGlobalPkgs = true;

    config = {
      config,
      lib,
      pkgs,
      ...
    }: {
      home.stateVersion = stateVersion;
      home.packages = with pkgs; [
        gnupg
        rbw
        pinentry-tty
      ];

      home = {
        file.".config/tmux".source = "${inputs.dots}/.config/tmux";
        file.".bash_aliases".source = "${inputs.dots}/.bash_aliases";
        file."clones/forks/xelabash".source = inputs.xelabash;
        file."scripts".source = "${inputs.dots}/scripts";
        file.".config/git".source = "${inputs.dots}/.config/git";
        # no secret-tool/D-Bus secret service on Termux, so this uses
        # pinentry-tty instead of the shared keyring-backed config
        file.".config/rbw/config.json".text = builtins.toJSON {
          email = "vaultwarden@marcel.cool";
          sso_id = null;
          base_url = "https://vault.marcel.cool";
          identity_url = null;
          ui_url = null;
          notifications_url = null;
          lock_timeout = 3600;
          sync_interval = 3600;
          pinentry = "pinentry-tty";
          client_cert_path = null;
        };
        file.".ssh/authorized_keys".text = sshKey;
        file.".ssh/sshd_config".text = ''
          Port 8022
          HostKey ${config.home.homeDirectory}/.ssh/ssh_host_ed25519_key
          AuthorizedKeysFile ${config.home.homeDirectory}/.ssh/authorized_keys
          StrictModes no
        '';
      };
      programs.ssh = {
        enable = true;
        matchBlocks = {
          "mlab" = {
            hostname = "ssh.marcel.cool";
            user = "dev";
            identityFile = "~/.ssh/id_mlab";
            extraOptions = {
              IdentitiesOnly = "yes";
            };
          };
        };
      };
      programs.bash = {
        enable = true;
        initExtra = ''
          source ${inputs.dots}/.bashrc
          if ! pgrep -f "sshd -f" >/dev/null; then
            if [ ! -f /data/data/com.termux.nix/files/home/.ssh/ssh_host_ed25519_key ]; then
              ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f /data/data/com.termux.nix/files/home/.ssh/ssh_host_ed25519_key -N "" -q
            fi
            # start daemon using the full path to the config
            /data/data/com.termux.nix/files/home/.nix-profile/bin/sshd -f /data/data/com.termux.nix/files/home/.ssh/sshd_config
          fi
        '';
      };
    };
  };
}
