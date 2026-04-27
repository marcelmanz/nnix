{
  config,
  pkgs,
  lib,
  inputs,
  services,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    inputs.home-manager.nixosModules.home-manager
    ./arr
    ./attic.nix
    ./audiobookshelf.nix
    ./authelia.nix
    ./calibre.nix
    ./ddclient.nix
    ./graphana.nix
    ./homepage.nix
    ./immich.nix
    ./invidious.nix
    ./jellyfin.nix
    ./miniflux.nix
    ./navidrome.nix
    ./ollama.nix
    ./open-webui.nix
    ./paperless.nix
    ./proxy.nix
    ./qbittorrent.nix
    ./sabnzbd.nix
    ./seafile.nix
    ./searxng.nix
    ./seerr.nix
    ./shoko.nix
    ./slskd.nix
    ./soulbeet.nix
    ./stalwart.nix
    ./uptime-kuma.nix
    # ./piped.nix
    # ./hyperpipe.nix
  ];

  time.timeZone = "Europe/Madrid";

  programs.mosh.enable = true;

  sops = {
    defaultSopsFile = ../../secrets/mlab.yaml;
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];

    secrets = {
      "app_pass" = {};
      "app_user" = {};
      "cloudflare_acme_token" = {};
      "invidious_companion_key" = {};
      "web_pass" = {};
      "web_user" = {};
      "grafana_secret_key" = {
        owner = "grafana";
      };
      "github_ssh_key" = {
        sopsFile = ../../secrets/github.yaml;
        owner = "dev";
        mode = "0600";
      };
    };

    templates."cloudflare-acme.env" = {
      content = "CF_DNS_API_TOKEN=${config.sops.placeholder.cloudflare_acme_token}";
      owner = "acme";
    };

    templates."invidious-extra.json" = {
      content = ''
        {"invidious_companion_key":"${config.sops.placeholder.invidious_companion_key}"}
      '';
      mode = "0444";
    };

    templates."invidious-companion.env" = {
      content = ''
        SERVER_SECRET_KEY=${config.sops.placeholder.invidious_companion_key}
      '';
      mode = "0444";
    };
  };

  users.groups.media.gid = 986;

  systemd.tmpfiles.rules = [
    # Shared Media Stack Base
    "d /var/lib/media 0775 root media -"

    # Set GID 2775 on download and import folders ensures
    # that files created by one app are writable by the whole 'media' group.
    "d /var/lib/media/downloads 2775 root media -"
    "d /var/lib/media/downloads/incomplete 2775 root media -"

    # Media Folders
    "d /var/lib/media/tv 0775 root media -"
    "d /var/lib/media/movies 0775 root media -"
    "d /var/lib/media/music 0775 root media -"
  ];

  services.postgresql = {
    enable = true;
    authentication = lib.mkForce ''
      # TYPE  DATABASE        USER            ADDRESS                 METHOD
      local   all             all                                     ident
      host    all             all             127.0.0.1/32            scram-sha-256
      host    all             all             ::1/128                 scram-sha-256
    '';
    ensureDatabases = ["navidrome" "paperless" "stalwart"];
    ensureUsers = [
      {
        name = "navidrome";
        ensureDBOwnership = true;
      }
      {
        name = "paperless";
        ensureDBOwnership = true;
      }
      {
        name = "stalwart";
        ensureDBOwnership = true;
      }
    ];
    settings = {
      # rule of thumb: 25% of total ram for shared_buffers
      shared_buffers = "8GB";
      effective_cache_size = "24GB";
      maintenance_work_mem = "2GB";
      checkpoint_completion_target = 0.9;
      wal_buffers = "16MB";
      autovacuum = "on";
      log_min_duration_statement = 500;
    };
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # for newer intel igpus
      intel-compute-runtime # OpenCL
      vpl-gpu-rt # Required for QSV on Intel 11th Gen and newer
    ];
  };

  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  networking = {
    hostName = "mlab";
    defaultGateway = "192.168.1.1";

    interfaces = {
      enp87s0 = {
        useDHCP = true;
        ipv4.addresses = [
          {
            address = "192.168.1.140";
            prefixLength = 24;
          }
        ];
      };
      enp2s0f0np0 = {
        useDHCP = true;
      };
      enp2s0f1np1 = {
        useDHCP = true;
      };
    };
    dhcpcd = {
      extraConfig = ''
        slaac private
        interface enp87s0
        noipv4
      '';
    };
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
    tempAddresses = "enabled";
    firewall = {
      enable = true;
      allowedTCPPorts =
        [
          80 # nginx catch-all / http to https redirects
          443 # Nginx HTTPS
          23951 # Qbitorrent
          50300 # Soulseek
        ]
        ++ builtins.map (v: v.port) (builtins.attrValues services);
      allowedUDPPorts = [23951];
      allowedUDPPortRanges = [
        {
          from = 60000;
          to = 61000;
        }
      ];
      extraCommands = ''
        # Allow traffic from Podman containers to the host
        iptables -A INPUT -i podman+ -p tcp --dport ${toString services.slskd.port} -j ACCEPT
        iptables -A INPUT -i podman+ -p tcp --dport ${toString services.navidrome.port} -j ACCEPT
      '';
      trustedInterfaces = ["podman0"];
    };
  };

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    tmp.cleanOnBoot = true;
    kernelParams = [
      "i915.enable_guc=3" # Forces GuC/HuC firmware loading for Low-Power encoding
    ];
  };

  services.logrotate.checkConfig = false;
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  security.pam.services.sshd.unixAuth = lib.mkForce true;
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      AllowAgentForwarding = true;
    };
    # Add specific ssh rules for user X
    # extraConfig = ''
    #   Match User X
    #     PasswordAuthentication yes
    #     KbdInteractiveAuthentication yes
    # '';
  };

  environment.systemPackages = with pkgs; [
    attic-client
    erdtree
    git
    vim
    lsof
    tree
    git
    duf
    jq
    ripgrep
    tmux
    neovim
    eza
    zoxide
    fd
    fzf
    bat
    bottom
    starship
    direnv
    sysz
    btop
    ethtool
    librespeed-cli
    libreswan
    ffmpeg_7
    atuin
    gnupg
    carapace
    mysql84
  ];

  environment.sessionVariables.NVIM_PROFILE = "minimal";

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];

    # optimization for 32gb + likely a multi-core cpu
    auto-optimise-store = true;
    cores = 0;
    max-jobs = "auto";
  };

  security.sudo.extraRules = [
    {
      groups = ["dev-team"];
      commands = [
        {
          command = "/run/current-system/sw/bin/systemctl restart atticd.service";
          options = ["NOPASSWD"];
        }
        {
          command = "/run/current-system/sw/bin/systemctl restart grafana.service";
          options = ["NOPASSWD"];
        }
        {
          command = "/run/current-system/sw/bin/systemctl restart prometheus.service";
          options = ["NOPASSWD"];
        }
        {
          command = "/run/current-system/sw/bin/systemctl restart uptime-kuma.service";
          options = ["NOPASSWD"];
        }
        {
          command = "/run/current-system/sw/bin/systemctl --system show *";
          options = ["NOPASSWD"];
        }
        {
          command = "/run/current-system/sw/bin/systemctl --system status *";
          options = ["NOPASSWD"];
        }
        {
          command = "/run/current-system/sw/bin/systemctl --system cat *";
          options = ["NOPASSWD"];
        }
        {
          command = "/run/current-system/sw/bin/systemctl --system list-units *";
          options = ["NOPASSWD"];
        }
        {
          command = "/run/current-system/sw/bin/systemctl --system list-unit-files *";
          options = ["NOPASSWD"];
        }
        {
          command = "/run/current-system/sw/bin/journalctl *";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];

  users = {
    groups.dev-team = {};

    users.dev = {
      isNormalUser = true;
      extraGroups = ["dev-team" "systemd-journal"];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN7c4J3kFLiJYHqUh9zkybQu0pjOu8tyofUnsd67se9m mlab server key"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIvff/camqPCFP3s0xfpjyMcw3y3V3/lEbh9Y1Q3Nj0M nix-on-droid@localhost"
      ];
    };
    users.root = {
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN7c4J3kFLiJYHqUh9zkybQu0pjOu8tyofUnsd67se9m mlab server key"
      ];
    };

    groups.media = {};
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {
      inherit inputs;
      inherit (inputs) nvim;
      inherit pkgs;
    };
    users.root = {
      home = {
        stateVersion = "26.05";
        file.".config/tmux".source = "${inputs.dots}/.config/tmux";
        file."scripts".source = "${inputs.dots}/scripts";
        file.".bash_aliases".source = "${inputs.dots}/.bash_aliases";
        file.".config/btop".source = "${inputs.dots}/.config/btop";
      };
    };
    users.dev = {lib, ...}: {
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
        matchBlocks."github.com" = {
          hostname = "github.com";
          user = "git";
          identityFile = "/run/secrets/github_ssh_key";
          extraOptions.IdentitiesOnly = "yes";
        };
      };
      home = {
        stateVersion = "26.05";
        sessionVariables.NVIM_PROFILE = "minimal";
        packages = with pkgs; [
          pass
          pi-coding-agent
          opencode
        ];
        file.".bash_aliases".source = "${inputs.dots}/.bash_aliases";
        file."clones/forks/xelabash".source = inputs.xelabash;
        file."scripts".source = "${inputs.dots}/scripts";
        file.".config/tmux".source = "${inputs.dots}/.config/tmux";
        file.".config/atuin".source = "${inputs.dots}/.config/atuin";
        file.".config/carapace".source = "${inputs.dots}/.config/carapace";
        file.".config/git".source = "${inputs.dots}/.config/git";
        file.".config/zoxide".source = "${inputs.dots}/.config/zoxide";
        file.".config/btop".source = "${inputs.dots}/.config/btop";
      };
      programs.bash = {
        enable = true;
        initExtra = ''
          source ${inputs.dots}/.bashrc
        '';
      };
      imports = [inputs.nvim.homeManagerModules.default];
    };
  };

  system.stateVersion = "26.05";
}
