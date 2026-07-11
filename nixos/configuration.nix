{
  config,
  pkgs,
  lib,
  username,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    # ./nixbuild-enabler.nix # enable this for external building with nixbuild.net
  ];

  boot = {
    binfmt.emulatedSystems = ["aarch64-linux"];
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };

  services.blueman.enable = true;

  programs.nix-ld.enable = true;

  nix.settings = {
    # cores = 0; # Use all cores

    auto-optimise-store = true;
    connect-timeout = 15;
    http-connections = 0;
    keep-derivations = true;
    keep-outputs = true;
    max-jobs = "auto";
    max-substitution-jobs = 128;
    warn-dirty = false;

    trusted-users = ["root" "marcel"];
    experimental-features = ["nix-command" "flakes"];

    substituters = [
      "https://cache.nixos.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "system:Ve/kZ+DnW135w7Z44yIxH0kOgIXoK6akWv282O2xmWM="
    ];
  };

  services.tailscale.enable = true;
  services.tailscale.extraSetFlags = ["--accept-dns=false"];

  networking.firewall.trustedInterfaces = ["tailscale0" "waydroid0"];
  networking.firewall.allowedUDPPorts = [config.services.tailscale.port];

  services.protonmail-bridge = {
    enable = true;
  };

  services.mpd = {
    enable = true;
    user = "marcel";
    startWhenNeeded = true;
    settings = {
      music_directory = "/home/marcel/techno-electronica/";
      audio_output = [
        {
          type = "pipewire";
          name = "PipeWire Output";
        }
      ];
    };
  };

  systemd.services.mpd.environment = {
    XDG_RUNTIME_DIR = "/run/user/1000";
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  networking.hostName = "nixos";
  services.fwupd.enable = true;

  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
    };
    bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings = {
        General = {
          Experimental = true;
          ReconnectAttempts = "0";
        };
      };
    };
  };
  services.flatpak.enable = true;

  virtualisation.waydroid = {
    enable = true;
  };

  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  networking = {
    # enableIPv6 = false;
    nameservers = ["1.1.1.1" "8.8.8.8"];
    networkmanager = {
      enable = true;
      plugins = with pkgs; [networkmanager-openvpn];
      # ponytail: router on "w-plus" pushes dead DHCP DNS (100.100.1.1/100.90.1.1) that
      # time out and make hostname resolution take ~13s -> breaks fast.com/browser.
      # Prepend working resolvers so glibc never tries the dead ones.
      insertNameservers = ["1.1.1.1" "8.8.8.8"];
    };
  };
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  time.timeZone = "Europe/Madrid";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # kde
  services.desktopManager.plasma6.enable = true;
  xdg.portal.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
  services.nzbget = {
    enable = true;
  };

  systemd.services.slskd.serviceConfig.ProtectHome = lib.mkForce false;

  systemd.tmpfiles.rules = [
    "d /home/${username}/music/downloads 0755 ${username} users -"
    "d /home/${username}/music/incompleted 0755 ${username} users -"
    "d /home/${username}/music/share 0755 ${username} users -"
  ];

  services.slskd = {
    enable = true;
    openFirewall = true;
    domain = null;
    user = username;
    group = "users";
    environmentFile = config.sops.templates."slskd.env".path;
    settings = {
      directories = {
        downloads = "/home/${username}/music/downloads";
        incomplete = "/home/${username}/music/incompleted";
      };
      shares = {
        directories = ["/home/${username}/music/share"];
      };
      soulseek = {
        listen_port = 50300;
        username = "mwallace";
      };
      web = {
        port = 5030;
        authentication = {
          username = username;
        };
      };
      global = {
        upload.slots = 10;
        download.slots = 10;
      };
    };
  };

  # services.ollama = {
  #   enable = true;
  # };

  systemd.services.ollama.environment = {
    OLLAMA_CONTEXT_LENGTH = "32768";
    OLLAMA_FLASH_ATTENTION = "1";
    OLLAMA_KEEP_ALIVE = "24h";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber = {
      enable = true;
    };
  };

  musnix.enable = false;

  users.users.marcel = {
    isNormalUser = true;
    description = "marcel";
    extraGroups = [
      "networkmanager"
      "wheel"
      "audio"
      "docker"
    ];
    packages = with pkgs; [
      kitty
    ];
  };

  services.dbus.enable = true;
  services.gnome.gnome-keyring.enable = true;

  services.xserver = {
    enable = true;
    windowManager.i3 = {
      enable = true;
      extraPackages = with pkgs; [dmenu];
    };
  };

  # plasma6 and seahorse both mkDefault this; pick plasma's ksshaskpass
  programs.ssh.askPassword = lib.mkForce "${pkgs.kdePackages.ksshaskpass.out}/bin/ksshaskpass";

  services.displayManager = {
    sddm = {
      enable = true;
      wayland.enable = true;
      theme = "breeze";
    };
    sessionPackages = [
      pkgs.hyprland
      pkgs.niri
    ];
    defaultSession = "hyprland";
  };

  programs.seahorse.enable = true;
  programs.hyprland.enable = true;
  programs.mosh.enable = true;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    pinentryPackage = pkgs.pinentry-curses;
    settings = {
      default-cache-ttl = 28800;
      max-cache-ttl = 86400;
    };
  };

  environment.systemPackages = with pkgs; [
    attic-client
    swaybg
    vim
    brave-origin
    neovim
    wget
    mullvad-vpn
    mullvad
    git
    gnumake
    usbutils
    networkmanagerapplet
    glib
    gcc
    gnupg
    pass-wayland
    openssl
    openvpn
    sbc
    chromium
    localsend
    proton-authenticator
    (pkgs.writeTextDir "share/sddm/themes/breeze/theme.conf.user" ''
      [General]
      background=/etc/sddm/black.png
    '')
  ];

  sops = {
    defaultSopsFile = ../secrets/nixos.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];

    secrets = {
      "SLSKD_SLSK_USERNAME" = {
        owner = username;
      };
      "SLSKD_SLSK_PASSWORD" = {
        owner = username;
      };
      "SLSKD_SOULSEEK_PASSWORD" = {
        owner = username;
      };
      "SLSKD_WEB_USERNAME" = {
        owner = username;
      };
      "SLSKD_WEB_PASSWORD" = {
        owner = username;
      };
      "SLSKD_USERNAME" = {
        owner = username;
      };
      "SLSKD_PASSWORD" = {
        owner = username;
      };
      "attic_token" = {};
      "github_ssh_key" = {
        sopsFile = ../secrets/github.yaml;
        owner = username;
        mode = "0600";
        path = "/home/${username}/.ssh/github_ed25519";
      };
    };

    templates."slskd.env" = {
      content = ''
        SLSKD_SLSK_USERNAME="${config.sops.placeholder.SLSKD_SLSK_USERNAME}"
        SLSKD_SLSK_PASSWORD="${config.sops.placeholder.SLSKD_SLSK_PASSWORD}"
        SLSKD_SOULSEEK_PASSWORD="${config.sops.placeholder.SLSKD_SOULSEEK_PASSWORD}"
        SLSKD_WEB_USERNAME="${config.sops.placeholder.SLSKD_WEB_USERNAME}"
        SLSKD_WEB_PASSWORD="${config.sops.placeholder.SLSKD_WEB_PASSWORD}"
        SLSKD_USERNAME="${config.sops.placeholder.SLSKD_USERNAME}"
        SLSKD_PASSWORD="${config.sops.placeholder.SLSKD_PASSWORD}"
      '';
      owner = username;
    };

    templates."attic-watch.env" = {
      content = ''
        ATTIC_TOKEN="${config.sops.placeholder.attic_token}"
      '';
    };
  };

  systemd.services.attic-watch-store = {
    description = "Attic Watch Store";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    after = ["network-online.target"];

    serviceConfig = {
      User = "root";
      EnvironmentFile = config.sops.templates."attic-watch.env".path;
      # Use a dedicated state directory for the attic config
      StateDirectory = "attic-client";
      ExecStartPre = pkgs.writeShellScript "attic-login" ''
        ${pkgs.attic-client}/bin/attic login mlab https://cache.marcel.cool "$ATTIC_TOKEN"
      '';
      ExecStart = "${pkgs.attic-client}/bin/attic watch-store mlab:system";
      Restart = "always";
    };
  };

  networking.firewall.enable = true;
  networking.nftables.enable = false;
  networking.networkmanager.wifi.powersave = false;

  users.users.marcel.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHe+ZUUCwet0+uaGYfr3hE4zNVASmQPWuoGpk5QAbKG4 nix-on-droid@localhost"
  ];

  system.stateVersion = "26.05";
}
