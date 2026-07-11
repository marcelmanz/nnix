{
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [inputs.nvim.homeManagerModules.default];

  home = {
    stateVersion = "26.05";
    sessionVariables.NVIM_PROFILE = "minimal";
    packages = with pkgs; [
      pass
      pi-coding-agent
      opencode
      gh
      fastfetch
      firefox
      brave-origin
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
    file.".config/foot/foot.ini".source = "${inputs.dots}/.config/foot/foot.ini";
    file.".config/foot/colors-light.ini".source = "${inputs.dots}/.config/foot/colors-light.ini";
    file.".config/foot/colors-dark.ini".source = "${inputs.dots}/.config/foot/colors-dark.ini";
    file.".config/foot/font-active.ini".text = "font=Myna:size=10";
    file.".pi/agent/settings.json" = {
      source = "${inputs.dots}/.pi/agent/settings.json";
      force = true;
    };
    file.".pi/agent/models.json" = {
      source = "${inputs.dots}/.pi/agent/models.json";
      force = true;
    };
    file.".pi/agent/mcp.json" = {
      source = "${inputs.dots}/.pi/agent/mcp.json";
      force = true;
    };
    file.".agents/skills/" = {
      source = "${inputs.dots}/.agents/skills";
      force = true;
    };

    # bashrc deps
    file.".bash-preexec.sh".source = "${inputs.dots}/.bash-preexec.sh";
    file.".inputrc".source = "${inputs.dots}/.inputrc";
  };

  programs.bash = {
    enable = true;
    initExtra = ''
      source ${inputs.dots}/.bashrc
      export SYNTHETIC_API_KEY="$(cat /run/secrets/synthetic_api_key 2>/dev/null)"
    '';
  };

  wayland.windowManager.sway = {
    enable = true;
    config = {
      modifier = "Mod1";
      terminal = "foot";
      menu = "tofi-run | xargs -r swaymsg exec --";
      window.titlebar = false;
      bars = [];
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
