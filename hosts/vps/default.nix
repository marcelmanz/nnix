{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    inputs.home-manager.nixosModules.home-manager
  ];

  systemd.tmpfiles.rules = [
    "d /var/lib/slskd 0755 slskd slskd -"
    "d /var/lib/slskd/music 0755 slskd slskd -"
    "d /var/lib/slskd/music/downloads 0755 slskd slskd -"
    "d /var/lib/slskd/music/incompleted 0755 slskd slskd -"
    "d /var/lib/slskd/music/share 0755 slskd slskd -"
    "d /etc/slskd 0755 slskd slskd -"
  ];

  systemd.services.slskd.serviceConfig = {
    ProtectSystem = lib.mkForce false;
    PrivateTmp = lib.mkForce false;
    ProtectHome = lib.mkForce false;
    PrivateDevices = lib.mkForce false;
    ProtectKernelTunables = lib.mkForce false;
    ProtectKernelModules = lib.mkForce false;
    ProtectControlGroups = lib.mkForce false;
    RestrictNamespaces = lib.mkForce false;
    ReadWritePaths = lib.mkForce [
      "/var/lib/slskd"
      "/var/lib/slskd/music"
      "/etc/slskd"
    ];
  };

  services.postgresql = {
    enable = true;
    authentication = lib.mkForce ''
      local all all trust
      host all all 127.0.0.1/32 trust
    '';
    ensureDatabases = ["navidrome"];
    ensureUsers = [
      {
        name = "navidrome";
        ensureDBOwnership = true;
      }
    ];
  };

  services.open-webui = {
    enable = true;
    host = "0.0.0.0";
    port = 3000;
  };

  services.caddy = {
    enable = true;
    virtualHosts."ai.marcel.cool" = {
      extraConfig = ''
        reverse_proxy 127.0.0.1:3000
      '';
    };
    virtualHosts = {
      # "photos.marcel.cool" = {
      #   extraConfig = ''
      #     @api path /api/*
      #     reverse_proxy @api 127.0.0.1:2283
      #     reverse_proxy 127.0.0.1:3001
      #   '';
      # };
      # "photos-server.marcel.cool" = {
      #   extraConfig = ''
      #     @api path /api/*
      #     reverse_proxy @api 127.0.0.1:2283
      #     reverse_proxy 127.0.0.1:3001
      #   '';
      # };
      "slskd.marcel.cool" = {
        extraConfig = ''
          reverse_proxy 127.0.0.1:5030
        '';
      };
      "music.marcel.cool" = {
        extraConfig = ''
          reverse_proxy 127.0.0.1:4533
        '';
      };
    };
  };

  services.slskd = {
    enable = true;
    openFirewall = true;
    domain = null;
    user = "slskd";
    group = "slskd";
    environmentFile = "/etc/slskd/credentials.env";
    settings = {
      directories = {
        downloads = "/var/lib/slskd/music/downloads";
        incomplete = "/var/lib/slskd/music/incompleted";
      };
      shares = {
        directories = ["/var/lib/slskd/music/share"];
      };
      soulseek = {
        listen_port = 50300;
      };
      web = {
        port = 5030;
        authentication = {
          enabled = true;
        };
      };
      global = {
        upload.slots = 10;
        download.slots = 10;
      };
    };
  };

  services.navidrome = {
    enable = true;
    user = "navidrome";
    group = "navidrome";
    settings = {
      DataFolder = "/var/lib/navidrome";
      Address = "0.0.0.0";
      Port = 4533;
      Auth = {
        Username = "admin";
        Password = "change-me-please";
      };
      MediaFolder = "/var/lib/slskd/music/share";
      DB = {
        Type = "postgres";
        Host = "127.0.0.1";
        Port = 5432;
        User = "navidrome";
        Password = "navidrome-pw";
        Database = "navidrome";
        SSLMode = "disable";
      };
    };
  };

  systemd.services.navidrome.serviceConfig.BindReadOnlyPaths = [
    "/var/lib/slskd/music/share"
  ];

  networking = {
    hostName = "marcel-cool-vps";
    firewall = {
      enable = true;
      allowedTCPPorts = [
        80
        443
        3000
        3001 # Immich UI
        2283 # Immich API
        5030 # slskd
        50300
        4533 # Navidrome
      ];
    };
  };

  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  boot.tmp.cleanOnBoot = true;

  services.logrotate.checkConfig = false;
  zramSwap.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = true;
      AllowAgentForwarding = true;
    };
  };

  environment.systemPackages = with pkgs; [
    git
    vim
    tree
    duf
    jq
    ripgrep
    tmux
  ];
  environment.sessionVariables.NVIM_PROFILE = "minimal";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  users = {
    users.dev = {
      isNormalUser = true;
      extraGroups = ["wheel"];
      packages = with pkgs; [
        neovim
        eza
        zoxide
        fd
        fzf
        bat
        bottom
        starship
        direnv
      ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII2bNnjQbOyc2j6yWvDbwfMLdv1Ej6/6QA77C1M05Awv"
      ];
    };

    users.root = {
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII2bNnjQbOyc2j6yWvDbwfMLdv1Ej6/6QA77C1M05Awv"
      ];
    };

    users.slskd = {
      isSystemUser = true;
      group = "slskd";
      home = "/var/lib/slskd";
      createHome = true;
    };
    groups.slskd = {};

    users.navidrome = {
      isSystemUser = true;
      group = "navidrome";
      extraGroups = ["slskd"];
      home = "/var/lib/navidrome";
      createHome = true;
    };
    groups.navidrome = {};
  };

  services.ollama = {
    enable = false; # not for now, we need more gpu in some way
  };

  services.immich = {
    enable = false; # disable for now

    settings = {
      server = {
        host = "0.0.0.0"; # frontend
        port = 3001;
      };
      api = {
        host = "0.0.0.0";
        port = 2283;
      };
    };
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {
      inherit inputs;
      inherit (inputs) nvim;
      inherit pkgs;
    };
    users.dev = {lib, ...}: {
      home = {
        stateVersion = "26.05";
        sessionVariables.NVIM_PROFILE = "minimal";
      };
      imports = [inputs.nvim.homeManagerModules.default];
    };
  };

  system.stateVersion = "26.05";
}
