{
  _config,
  pkgs,
  _lib,
  ...
}: let
  # Myna: custom monospace font (github.com/sayyadirfanali/Myna).
  myna-font = pkgs.runCommand "myna-font" {} ''
    install -Dm644 ${pkgs.fetchFromGitHub {
      owner = "sayyadirfanali";
      repo = "Myna";
      rev = "60204ed5dfce2d821a46a73d27bee902986b3462";
      hash = "sha256-b7rzuPl5bkEYVLoY1bflsVlR69obD28edxUvMf8sm84=";
    }}/Myna.otf $out/share/fonts/truetype/Myna.otf
  '';
in {
  fonts.packages = [ myna-font ];
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings.General.Experimental = true;
  };

  programs.sway = {
    # it will not run on boot
    enable = true;
    extraPackages = with pkgs; [
      foot
      tofi
      wl-clipboard
      grim
      slurp
      swappy
      libnotify
      bluetuith # bluetooth tui
    ];
  };
  security.polkit.enable = true;

  home-manager.users.dev = {
    pkgs,
    lib,
    ...
  }: {
    wayland.windowManager.sway = {
      enable = true;
      config = {
        modifier = "Mod1";
        terminal = "foot";
        menu = "tofi-run | xargs -r swaymsg exec --";
        output."HDMI-A-1" = {
          resolution = "3840x2160@60Hz";
          scale = "1.67";
        };
        keybindings = lib.mkOptionDefault {
          "Mod1+q" = "exec brave-origin-nightly";
          "Mod1+b" = "exec ~/scripts/bluetooth-selector.sh";
          "Mod1+Shift+b" = "exec foot -e bluetuith";
          "Mod1+Print" = ''exec grim -g "$(slurp)" - | swappy -f -'';
          "Mod1+v" = "floating toggle";
          "Mod1+Shift+r" = "reload";
          "Mod1+h" = "focus left";
          "Mod1+j" = "focus down";
          "Mod1+k" = "focus up";
          "Mod1+l" = "focus right";
          "Mod1+Shift+h" = "move left";
          "Mod1+Shift+j" = "move down";
          "Mod1+Shift+k" = "move up";
          "Mod1+Shift+l" = "move right";
        };
      };
    };

    home.packages = with pkgs; [
      firefox # always good to have it
      brave-origin
    ];
  };
}
