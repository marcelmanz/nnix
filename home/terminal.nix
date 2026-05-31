{
  config,
  pkgs,
  inputs ? null,
  pkgsStable ? null,
  ...
}: let
  homeDir = config.home.homeDirectory;
  pstore = "${homeDir}/clones/own/password-store";
  terminalPackages = import ./terminal-packages.nix {inherit config pkgs pkgsStable;};
in {
  home.stateVersion = "26.05";
  programs.home-manager.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
    OPENSSL_DIR = "${pkgs.openssl.out}";
    OPENSSL_LIB_DIR = "${pkgs.openssl.out}/lib";
    OPENSSL_INCLUDE_DIR = "${pkgs.openssl.dev}/include";
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
    USE_GKE_GCLOUD_AUTH_PLUGIN = "True";
  };

  services.ollama = {
    enable = true;
  };

  home.packages =
    terminalPackages
    ++ (with pkgs; [
      tmex
      _1password-cli
      alejandra
      asciinema
      # nvim-nightly
      jdd
      sops
      age
      playwright-driver.browsers
    ]);

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      "github.com" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/github_ed25519";
        extraOptions = {
          IdentitiesOnly = "yes";
        };
      };
      "bitbucket.org" = {
        hostname = "bitbucket.org";
        user = "git";
        identityFile = "~/.ssh/id_rsa_bitbucket";
        extraOptions = {
          LogLevel = "ERROR";
        };
      };
      "codeberg.org" = {
        hostname = "codeberg.org";
        user = "git";
        identityFile = "~/.ssh/id_ed25519_codeberg";
        extraOptions = {
          IdentitiesOnly = "yes";
        };
      };
      "vps" = {
        hostname = "204.168.128.208";
        user = "git";
        identityFile = "~/.ssh/hetzner_ai";
        extraOptions = {
          IdentitiesOnly = "yes";
        };
      };
      "mlab" = {
        hostname = "ssh.marcel.cool";
        user = "root";
        identityFile = "~/.ssh/mlab_key";
        extraOptions = {
          IdentitiesOnly = "yes";
        };
      };
      "mlab-local" = {
        hostname = "192.168.1.140";
        user = "root";
        identityFile = "~/.ssh/mlab_key";
        extraOptions = {
          IdentitiesOnly = "yes";
        };
      };
      "droid" = {
        hostname = "100.112.164.46";
        user = "nix-on-droid";
        port = 8022;
        identityFile = "~/.ssh/id_ed25519";
        extraOptions = {
          IdentitiesOnly = "yes";
          ServerAliveInterval = "60";
        };
      };
    };
  };

  home.file = let
    link = config.lib.file.mkOutOfStoreSymlink;
    clonesOwn = "${homeDir}/clones/own";
    dots = "${clonesOwn}/dots";
    nvim = "${clonesOwn}/nvim";
    notes = "${clonesOwn}/notes";
  in {
    ".vimrc".source = link "${dots}/.vimrc";
    ".gitconfig".source = link "${dots}/.gitconfig";
    ".gitignore".source = link "${dots}/.gitignore";
    ".bashrc".source = link "${dots}/.bashrc";
    ".bash_aliases".source = link "${dots}/.bash_aliases";
    ".bash-preexec.sh".source = link "${dots}/.bash-preexec.sh";
    ".config/starship.toml".source = link "${dots}/.config/starship.toml";
    ".config/shellcheckrc".source = link "${dots}/.config/shellcheckrc";
    # ".cargo/env".source = link "${dots}/.cargo/env";
    # ".cargo/env.fish".source = link "${dots}/.cargo/env.fish";
    # ".cargo/env.nu".source = link "${dots}/.cargo/env.nu";
    ".inputrc".source = link "${dots}/.inputrc";
    ".taskrc".source = link "${dots}/.taskrc";
    ".config/direnv/direnv.toml".source = link "${dots}/.config/direnv/direnv.toml";
    ".config/clangd/config.yaml".source = link "${dots}/.config/clangd/config.yaml";
    ".claude/settings.json".source = link "${dots}/.claude/settings.json";
    ".config/btop/btop.conf".source = link "${dots}/.config/btop/btop.conf";

    # codex
    ".codex/AGENTS.md".source = link "${dots}/.codex/AGENTS.md";
    # claude
    ".claude/AGENTS.md".source = link "${dots}/.codex/AGENTS.md";

    # ".claude/CLAUDE.md".source = link "${dots}/.claude/CLAUDE.md";
    ".claude/CLAUDE.md".source = link "${dots}/.codex/AGENTS.md";

    "scripts" = {
      source = link "${dots}/scripts";
      recursive = true;
    };

    ".config/erdtree" = {
      source = link "${dots}/.config/erdtree";
      recursive = true;
    };

    ".task" = {
      source = link "${dots}/.tasks";
      recursive = true;
    };

    ".password-store" = {
      source = link "${pstore}/";
      recursive = true;
    };

    ".config/fish" = {
      source = link "${dots}/.config/fish";
      recursive = true;
    };

    ".config/nushell" = {
      source = link "${dots}/.config/nushell";
      recursive = true;
    };

    ".config/tmux" = {
      source = link "${dots}/.config/tmux";
      recursive = true;
    };

    ".config/cbfmt" = {
      source = link "${dots}/.config/cbfmt";
      recursive = true;
    };

    ".config/nvim" = {
      source = link nvim;
      recursive = true;
    };

    ".config/eza" = {
      source = link "${dots}/.config/eza";
      recursive = true;
    };

    ".config/bat" = {
      source = link "${dots}/.config/bat";
      recursive = true;
    };

    ".config/beets" = {
      source = link "${dots}/.config/beets";
      recursive = true;
    };

    ".config/vale" = {
      source = link "${dots}/.config/vale";
      recursive = true;
    };

    ".config/opencode" = {
      source = link "${dots}/.config/opencode";
      recursive = true;
    };

    ".config/tombi" = {
      source = link "${dots}/.config/tombi";
      recursive = true;
    };

    ".config/zellij" = {
      source = link "${dots}/.config/zellij";
      recursive = true;
    };

    ".config/zk" = {
      source = link "${dots}/.config/zk";
      recursive = true;
    };
    ".config/cliflux" = {
      source = link "${dots}/.config/cliflux";
      recursive = true;
    };
    ".pi" = {
      source = link "${dots}/.pi";
      recursive = true;
    };
    ".newsboat" = {
      source = link "${dots}/.newsboat";
      recursive = true;
    };

    "notes" = {
      source = link notes;
      recursive = true;
    };

    # ".kube" = {
    #   source = link "${dots}/.kube";
    #   recursive = true;
    # };
  };
}
