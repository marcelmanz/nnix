{
  _config,
  pkgs,
  _lib,
  ...
}: {
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
      bluetuith # TUI: scan/pair/trust/connect new devices
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
        menu = "tofi-run";
        # 4K on HDMI-A-1; scale matches hyprland monitors.conf (1.67).
        output."HDMI-A-1" = {
          resolution = "3840x2160@60Hz";
          scale = "1.67";
        };
        keybindings = lib.mkOptionDefault {
          "Mod1+Q" = "exec brave-origin-nightly";
          "Mod1+D" = "exec tofi-run";
          "Mod1+B" = "exec ~/scripts/bluetooth-selector.sh";
          "Mod1+Shift+B" = "exec foot -e bluetuith";
          "Mod1+Print" = ''exec grim -g "$(slurp)" - | swappy -f -'';

          "Mod1+Shift+Q" = "kill";
          "Mod1+F" = "fullscreen toggle";
          "Mod1+V" = "floating toggle";
          "Mod1+Shift+R" = "reload";

          "Mod1+H" = "focus left";
          "Mod1+J" = "focus down";
          "Mod1+K" = "focus up";
          "Mod1+L" = "focus right";
          "Mod1+Shift+H" = "move left";
          "Mod1+Shift+J" = "move down";
          "Mod1+Shift+K" = "move up";
          "Mod1+Shift+L" = "move right";
        };
      };
    };

    home.packages = with pkgs; [
      firefox # always good to have it
      brave-origin
    ];
  };
}
