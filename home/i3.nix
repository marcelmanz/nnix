{
  config,
  pkgs,
  lib,
  ...
}: {
  xsession.windowManager.i3 = {
    enable = true;
    config = {
      modifier = "Mod1";
      terminal = "kitty";
      menu = "dmenu_run";
      window.titlebar = false;
      bars = [];
      keybindings = lib.mkOptionDefault {
        "Mod1+q" = "exec brave-origin-nightly";
        "Mod1+Print" = "exec flameshot gui";
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
    extraConfig = ''
      gaps inner 5
      gaps outer 5
      default_border pixel 1
      default_floating_border pixel 1
      client.focused          #007f86 #007f86 #e0e4de #007f86
      client.focused_inactive #64666c #64666c #e0e4de #64666c
      client.unfocused        #64666c #e0e4de #2c2e33 #64666c
      client.urgent           #350775 #350775 #e0e4de #350775
    '';
  };
}
