# Shared cli only package list for both home-manager and nix-on-droid
{
  config,
  pkgs,
  pkgsStable ? pkgs,
}:
with pkgs; [
  # aider-chat
  # helix
  # helix
  # libreoffice
  # libreoffice
  # lsv
  # pi-undo-redo
  # pi-undo-redo
  # rff
  # zuban
  appimage-run
  astro-language-server
  atool
  atuin
  bacon
  basedpyright
  bash
  bash-language-server
  bash-preexec
  bat
  beets
  bind
  biome
  bottom
  btop
  carapace
  carl
  cbfmt
  chafa
  charm-freeze
  clang-tools
  claude-code
  click
  cliflux
  codex
  cowsay
  cowsay
  csvlens
  csvlens
  delta
  deno
  difftastic
  direnv
  dprint
  duf
  dump
  emmylua-ls
  erdtree
  eslint_d
  evtest
  eza
  fastfetch
  fd
  fennel-ls
  ffmpeg
  fish
  fixjson
  flyctl
  frogmouth
  fx
  fzf
  fzy
  gcalcli
  gcc
  gdrive
  gh
  git-cliff
  git-commit-search
  gitFull
  glirc
  glirc
  glow
  gnumake
  gping
  gst_all_1.gstreamer
  haralyzer
  hcloud
  htmlq
  htop
  hyprland-workspaces
  imagemagick
  iptables
  jaq
  java-language-server
  jq
  jujutsu
  just
  killall
  kubectl
  kubectx
  lazygit
  libnotify
  librespeed-cli
  libwebp
  lsr
  luau
  markdown-oxide
  marksman
  mdformat
  mdwatch
  mdwatch
  mdx-language-server
  mediainfo
  moor
  mpc
  murex
  ncdu
  neovim
  newsboat
  nftables
  nil
  nix-diff
  nix-search-cli
  nixfmt
  nnn
  nodejs_22
  noisetorch
  nuit
  nushell
  nwg-displays
  onefetch
  opencode
  openssl
  optipng
  pamixer
  parted
  pass-wayland
  passff-host
  patchutils
  pfetch
  pkgsStable.slsk-batchdl
  playerctl
  poppler-utils
  prefetch-npm-deps
  prettier
  prettierd
  prettierd
  pulseaudio-next-output
  pulseaudio-next-output
  pulseaudioFull
  pwgen
  rabbitmqadmin-ng
  rclone
  repgrep
  rich-cli
  ripgrep
  rmpc
  ruby
  rustup
  sendme
  shellcheck
  shfmt
  slskd
  socat
  solargraph
  sox
  speedtest-cli
  speedtest-rs
  sqlfluff
  sqlite
  sshfs
  starship
  stylua
  svelte-language-server
  sysz
  tailwindcss-language-server
  taplo
  taskwarrior-tui
  taskwarrior3
  tig
  timer
  tldr
  tmux
  traceroute
  tree
  trippy
  typos
  typos
  typos-lsp
  typos-lsp
  typst
  unrar
  unzip
  util-linux
  uv
  v4l-utils
  v4l-utils
  vale
  vale-ls
  vscode-langservers-extracted
  vtsls
  w3m
  watchexec
  wireguard-tools
  wlr-layout-ui
  wlr-randr
  wob
  xan
  yt-dlp
  ytfzf
  zbar
  zellij
  zeroclaw
  zk
  zoxide
  zsh
  (pkgs.symlinkJoin {
    # then install the following:
    # pi install npm:@mjakl/pi-kagi-search
    name = "pi-coding-agent";
    buildInputs = [pkgs.makeWrapper];
    paths = [pkgs.pi-coding-agent];
    postBuild = ''
      wrapProgram $out/bin/pi \
        --set NPM_CONFIG_PREFIX ${config.home.homeDirectory}/.pi/npm/ \
        --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.nodejs_latest
        ]
      }
    '';
  })
  (pkgs.python3.withPackages (ps:
    with ps; [
      python-lsp-server
      pylsp-rope
      pyflakes
      jedi
      mccabe
      pycodestyle
      black
      isort
    ]))
  (pkgs.google-cloud-sdk.withExtraComponents (with pkgs.google-cloud-sdk.components; [gke-gcloud-auth-plugin]))
]
