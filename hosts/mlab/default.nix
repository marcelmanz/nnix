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
    ./dropbox.nix
    ./graphana.nix
    ./homepage.nix
    ./immich.nix
    ./invidious.nix
    ./jellyfin.nix
    ./livekit.nix
    ./miniflux.nix
    ./navidrome.nix
    ./ollama.nix
    ./open-webui.nix
    ./paperless.nix
    ./pinchflat.nix
    ./proxy.nix
    ./qbittorrent.nix
    ./sabnzbd.nix
    ./seafile.nix
    ./searxng.nix
    ./seerr.nix
    ./shoko.nix
    ./slskd.nix
    ./sway.nix
    ./soulbeet.nix
    ./stalwart.nix
    ./uptime-kuma.nix
    ./matrix.nix
    ./vaultwarden.nix
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
      "livekit_api_secret" = {};
      "livekit_api_key" = {};
      "synthetic_api_key" = {
        owner = "dev";
        mode = "0400";
      };
      "ms01_admin_hash" = {neededForUsers = true;};
      "ms01_dev_hash" = {neededForUsers = true;};
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

    # ponytail: shared rendered secret, format "KEY: SECRET" (space after colon).
    # lk-jwt LIVEKIT_KEY_FILE splits on ":" then trims ws; livekit-server --key-file
    # YAML-unmarshals into map[string]string (needs the space to be a map, not a
    # scalar). The old LIVEKIT_KEYS= prefix leaked into lk-jwt's parsed key and
    # livekit's separate /etc file had unrendered sops placeholders.
    templates."livekit-secrets" = {
      content = "${config.sops.placeholder.livekit_api_key}: ${config.sops.placeholder.livekit_api_secret}";
      owner = "root";
      mode = "0600";
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
      local   all             all                                     trust
      host    all             all             127.0.0.1/32            scram-sha-256
      host    all             all             ::1/128                 scram-sha-256
    '';
    ensureDatabases = ["navidrome" "paperless" "stalwart" "matrix"];
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
      {
        name = "matrix";
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
    useNetworkd = true;
    useDHCP = false;
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
    # Use dnsmasq as a DNS forwarder to bypass ISP DNS that DHCP may return
    hosts = {
      "127.0.0.1" = ["marcel.cool"];
    };
    tempAddresses = "enabled";
    firewall = {
      enable = true;
      allowedTCPPorts =
        [
          53 # DNS (dnsmasq) so router/LAN clients can redirect here
          80 # nginx catch-all / http to https redirects
          443 # Nginx HTTPS
          23951 # Qbitorrent
          50300 # Soulseek
        ]
        ++ builtins.map (v: v.port) (builtins.attrValues services);
      allowedUDPPorts = [53 23951];
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

  systemd.network = {
    enable = true;
    wait-online.enable = false;
    networks = {
      "10-lan10g" = {
        # Wavlink 10G (atlantic) — primary cable NIC
        matchConfig.MACAddress = "80:3f:5d:fd:d0:35";
        address = ["192.168.1.140/24"];
        routes = [{Gateway = "192.168.1.1";}];
        networkConfig = {
          DHCP = "ipv6"; # SLAAC/DHCPv6 only; static IPv4 (was dhcpcd noipv4)
          # RFC 7217 opaque addr (no MAC leak). Was dhcpcd "slaac private".
          IPv6LinkLocalAddressGenerationMode = "stable-privacy";
        };
      };
      "20-lan2g5" = {
        # Built-in 2.5G (igc) — fallback cable NIC, same .140
        matchConfig.MACAddress = "38:05:25:35:30:0a";
        address = ["192.168.1.140/24"];
        routes = [{Gateway = "192.168.1.1";}];
        networkConfig = {
          DHCP = "ipv6";
          IPv6LinkLocalAddressGenerationMode = "stable-privacy";
        };
      };
      "30-sfp0" = {
        # SFP+ port 0 (i40e) — DHCP if ever plugged
        matchConfig.MACAddress = "38:05:25:35:30:08";
        networkConfig = {
          DHCP = "yes";
          IPv6LinkLocalAddressGenerationMode = "stable-privacy";
        };
      };
      "31-sfp1" = {
        # SFP+ port 1 (i40e) — DHCP if ever plugged
        matchConfig.MACAddress = "38:05:25:35:30:09";
        networkConfig = {
          DHCP = "yes";
          IPv6LinkLocalAddressGenerationMode = "stable-privacy";
        };
      };
    };
  };

  services.dnsmasq.enable = true;
  services.dnsmasq.settings = {
    interface = "enp1s0";
    bind-interfaces = true;
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
    extraConfig = ''
      Subsystem sftp internal-sftp -l INFO

      # admin is local console only
      DenyUsers admin

      Match User dev
        PasswordAuthentication yes
        KbdInteractiveAuthentication yes
    '';
  };

  environment.systemPackages = with pkgs; [
    attic-client
    atuin
    bat
    bottom
    btop
    carapace
    direnv
    duf
    erdtree
    ethtool
    eza
    fd
    ffmpeg_7
    fzf
    git
    gnupg
    jq
    librespeed-cli
    libreswan
    lsof
    mysql84
    neovim
    ripgrep
    starship
    sysz
    tmux
    tree
    vim
    waypipe
    zoxide
    thunar
    sqlite
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
          command = "/run/current-system/sw/bin/systemctl reload *";
          options = ["NOPASSWD"];
        }
        {
          command = "/run/current-system/sw/bin/nix-collect-garbage -d";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];

  users = {
    mutableUsers = false; # nix overrides the user password specified in the sops hashes
    groups.dev-team = {};

    # dev: ssh key + password over ssh + local console. Same perms as before (limited sudo via dev-team).
    users.dev = {
      isNormalUser = true;
      hashedPasswordFile = config.sops.secrets."ms01_dev_hash".path;
      extraGroups = ["dev-team" "systemd-journal"];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN7c4J3kFLiJYHqUh9zkybQu0pjOu8tyofUnsd67se9m mlab server key"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIvff/camqPCFP3s0xfpjyMcw3y3V3/lEbh9Y1Q3Nj0M nix-on-droid@localhost"
      ];
    };

    users.admin = {
      isNormalUser = true;
      hashedPasswordFile = config.sops.secrets."ms01_admin_hash".path;
      extraGroups = ["wheel"];
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
    backupFileExtension = "backup";
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
    users.dev = {
      imports = [./home.nix];
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
    };

    users.admin = {
      imports = [./home.nix];
    };
  };

  system.stateVersion = "26.05";
}
