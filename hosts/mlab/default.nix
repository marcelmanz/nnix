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
    inputs.pir.nixosModules.pir-server
    ./arr
    ./attic.nix
    ./audiobookshelf.nix
    ./authelia.nix
    ./azuracast
    ./bandcampsync.nix
    ./brave-origin-bump.nix
    ./calibre.nix
    ./ddclient.nix
    ./dropbox.nix
    ./graphana.nix
    ./homepage.nix
    ./immich.nix
    ./invidious
    ./jellyfin.nix
    ./livekit.nix
    ./matrix.nix
    ./mautrix-whatsapp.nix
    ./miniflux.nix
    ./navidrome.nix
    ./nitter.nix
    ./offtiktok.nix
    ./ollama.nix
    ./open-webui.nix
    ./paperless.nix
    ./pinchflat.nix
    ./proxy.nix
    ./qbittorrent.nix
    ./redroid.nix
    ./sabnzbd.nix
    ./seafile.nix
    ./searxng.nix
    ./seerr.nix
    ./shoko.nix
    ./slskd.nix
    ./soulbeet.nix
    ./sway.nix
    ./syncthing.nix
    ./uptime-kuma.nix
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
      "codeberg_ssh_key" = {
        owner = "dev";
        mode = "0600";
      };
      "codeberg_dev_ssh_key" = {
        owner = "dev";
        mode = "0600";
      };
      "codeberg_dev_token" = {
        owner = "dev";
        mode = "0400";
      };
      "livekit_api_secret" = {};
      "livekit_api_key" = {};
      "mautrix_whatsapp_pickle_key" = {owner = "mautrix-whatsapp";};
      "synthetic_api_key" = {
        owner = "dev";
        mode = "0400";
      };
      "ms01_admin_hash" = {neededForUsers = true;};
      "ms01_dev_hash" = {neededForUsers = true;};
      "ytify_user_password" = {};
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

    templates."livekit-secrets" = {
      content = "${config.sops.placeholder.livekit_api_key}: ${config.sops.placeholder.livekit_api_secret}";
      owner = "root";
      mode = "0600";
    };

    templates."mautrix-whatsapp.env" = {
      content = "ENCRYPTION_PICKLE_KEY=${config.sops.placeholder.mautrix_whatsapp_pickle_key}";
      owner = "mautrix-whatsapp";
      mode = "0400";
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
    # Owner 1000 (dev on host == azuracast in the container): AzuraCast writes
    # .albumart/.covers cache dot-dirs at this root. The container's UID 1000
    # worker can't use the media group for write — podman --group-add=986 only
    # reaches PID 1; supervisord's setuid workers call initgroups("azuracast")
    # which resets to the container /etc/group (no 986 entry). Owner-write avoids
    # that; group media (986) is preserved so navidrome/slskd/bandcampsync keep
    # access. Music files inside stay 0644 root:root (read-only to all).
    "d /var/lib/media/music 0775 1000 media -"
  ];

  services.postgresql = {
    enable = true;
    authentication = lib.mkForce ''
      # TYPE  DATABASE        USER            ADDRESS                 METHOD
      # synapse runs as matrix-synapse but owns the db as matrix, so it needs the map
      local   all             matrix                                  peer map=synapse
      local   all             all                                     peer
      host    all             all             127.0.0.1/32            scram-sha-256
      host    all             all             ::1/128                 scram-sha-256
    '';
    identMap = ''
      # MAP     SYSTEM-USER      PG-USER
      synapse   matrix-synapse   matrix
    '';
    ensureDatabases = ["navidrome" "paperless" "matrix"];
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

  virtualisation.libvirtd = {
    enable = true;
    qemu.swtpm.enable = true;
  };

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
      # Only ports that must be reachable off-host. Services in proxy.nix are
      # fronted by nginx over loopback - do not list their backend ports here.
      allowedTCPPorts = [
        53 # DNS (dnsmasq), LAN only - see local-service below
        80 # nginx catch-all / http to https redirects
        443 # Nginx HTTPS
        23951 # qBittorrent torrent port
        50300 # Soulseek peer port
      ];
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
          IPv6LinkLocalAddressGenerationMode = "stable-privacy";
          # networkd's IPv6PrivacyExtensions overrides networking.tempAddresses on
          # interfaces it manages; "yes" prefers a temporary address for outbound.
          IPv6PrivacyExtensions = "yes";
          # This USB 10G adapter drops carrier for ~5s several times a day (kernel:
          # "atlantic: link change old 10000 new 0"). By default networkd tears the whole IP
          # config down on carrier loss and re-acquires on return ("DHCPv6 lease lost"),
          # which turns a 5s physical blip into a much longer outage for every established
          # connection - listeners' audio streams included. Ride out short flaps instead:
          # keep addresses/routes/leases across a carrier loss up to 60s.
          IgnoreCarrierLoss = "60s";
        };
        ipv6AcceptRAConfig.Token = "prefixstable";
      };
      "20-lan2g5" = {
        # Built-in 2.5G (igc) — fallback cable NIC, same .140
        matchConfig.MACAddress = "38:05:25:35:30:0a";
        address = ["192.168.1.140/24"];
        routes = [{Gateway = "192.168.1.1";}];
        networkConfig = {
          DHCP = "ipv6";
          IPv6LinkLocalAddressGenerationMode = "stable-privacy";
          IPv6PrivacyExtensions = "yes"; # see 10-lan10g above
        };
        ipv6AcceptRAConfig.Token = "prefixstable";
      };
      "30-sfp0" = {
        # SFP+ port 0 (i40e) — DHCP if ever plugged
        matchConfig.MACAddress = "38:05:25:35:30:08";
        networkConfig = {
          DHCP = "yes";
          IPv6LinkLocalAddressGenerationMode = "stable-privacy";
        };
        ipv6AcceptRAConfig.Token = "prefixstable";
      };
      "31-sfp1" = {
        # SFP+ port 1 (i40e) — DHCP if ever plugged
        matchConfig.MACAddress = "38:05:25:35:30:09";
        networkConfig = {
          DHCP = "yes";
          IPv6LinkLocalAddressGenerationMode = "stable-privacy";
        };
        ipv6AcceptRAConfig.Token = "prefixstable";
      };
    };
  };

  services.dnsmasq.enable = true;
  services.dnsmasq.settings = {
    interface = "enp1s0";
    bind-interfaces = true;
    # Answer only queries from directly-attached subnets.
    local-service = true;
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

  services.fail2ban = {
    enable = true;
    ignoreIP = [
      "127.0.0.0/8"
      "192.168.0.0/24"
      "192.168.1.0/24"
    ];
    bantime-increment.enable = true;
    jails = {
      sshd.settings = {
        enabled = true;
        backend = "systemd";
        maxretry = 5;
        findtime = "10m";
        bantime = "1h";
      };

      authelia = {
        filter.Definition = {
          failregex = ''^.*Unsuccessful .*attempt by user .*remote_ip="?<HOST>"?.*$'';
          journalmatch = "_SYSTEMD_UNIT=authelia-main.service";
        };
        settings = {
          enabled = true;
          backend = "systemd";
          port = "80,443";
          maxretry = 5;
          findtime = "10m";
          bantime = "1h";
        };
      };

      nginx-botsearch.settings = {
        enabled = true;
        filter = "nginx-botsearch";
        backend = "polling";
        logpath = "/var/log/nginx/access.log";
        port = "80,443";
        maxretry = 10;
        findtime = "10m";
        bantime = "1h";
      };

      nginx-bad-request.settings = {
        enabled = true;
        filter = "nginx-bad-request";
        backend = "polling";
        logpath = "/var/log/nginx/access.log";
        port = "80,443";
        maxretry = 10;
        findtime = "10m";
        bantime = "1h";
      };
    };
  };

  environment.systemPackages = with pkgs; [
    attic-client
    atuin
    bat
    bottom
    btop
    carapace
    duf
    erdtree
    ethtool
    eza
    fd
    ffmpeg_7
    fzf
    gdu
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
    dua
    dust
    python3
  ];

  environment.sessionVariables.NVIM_PROFILE = "minimal";

  nix = {
    package = pkgs.lixPackageSets.stable.lix;
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      cores = 0;
      max-jobs = "auto";
    };
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
        # restricted nix builder key (work laptop); serve+write only, no shell
        "restrict,command=\"nix-store --serve --write\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPSTGnRIsqtRehW+QjAUmmtexnE+zx1Lkhp+WaQcTAUQ nix-builder@work"
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
        settings."github.com" = {
          HostName = "github.com";
          User = "git";
          IdentityFile = "/run/secrets/github_ssh_key";
          IdentitiesOnly = "yes";
        };
        settings."codeberg.org" = {
          HostName = "codeberg.org";
          User = "git";
          IdentityFile = "/run/secrets/codeberg_dev_ssh_key";
          IdentitiesOnly = "yes";
        };
      };
    };

    users.admin = {
      imports = [./home.nix];
    };
  };

  system.stateVersion = "26.05";

  services.pir = {
    enable = true;
    user = "dev";
  };
}
