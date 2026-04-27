This is my Nix setup managing multiple configurations with a modular structure:
- **nixos**: Full desktop setup with GUI applications
- **work**: Also full desktop setup but for a secondary work host
- **android**: Terminal-only setup for nix-on-droid
- **mlab**: Homelab config

The configurations use a layered approach:
- `terminal-packages.nix`: Shared CLI package list function
- `terminal.nix`: Home-manager module with CLI tools + terminal file configs  
- `gui.nix`: Imports terminal.nix + adds GUI applications and desktop configs

- NixOS documentation [here](https://nixos.org/manual/nixos/unstable/)
- Flakes info [here](https://wiki.nixos.org/wiki/Flakes)

## Usage

Build NixOS config (GUI + terminal):
```bash
sudo nixos-rebuild switch --flake ~/.config/nix#nixos
```

Build work config (GUI + terminal but with work home):
```bash
home-manager switch --flake ~/.config/nix#work
```

Build Android config (terminal only):
```bash
nix-on-droid switch --flake ~/.config/nix#default
```

## Structure
```bash
.
├── flake.lock
├── flake.nix
├── home
│   ├── gui.nix               # GUI apps + imports terminal.nix
│   ├── terminal.nix          # Home-manager CLI module + configs
│   └── terminal-packages.nix # Shared CLI package list
├── hosts
│   ├── android
│   │   ├── bootstrap.nix
│   │   ├── default.nix
│   │   ├── GUIDE.md
│   │   └── ssh.pub
│   ├── home
│   │   └── default.nix       # imports gui.nix
│   └── work
│       └── default.nix       # imports terminal.nix
│   ├── infected-vps
│   │   └── default.nix
│   ├── mlab                  # homelab config
│   │   ├── arr
│   │   │   ├── bazarr.nix
│   │   │   └── etc...
│   │   ├── attic.nix
│   │   ├── audiobookshelf.nix
│   │   ├── authelia.nix
│   │   ├── etc...
│   ├── vps                   # external vps, for quick deploys
│   │   ├── default.nix
│   │   ├── disk-config.nix
│   │   └── hardware-configuration.nix
├── nixos
│   ├── configuration.nix
│   └── hardware-configuration.nix
└── README.md
```

## Todo

- [x] Finish android host 
