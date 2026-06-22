{
  _config,
  pkgs,
  _lib,
  ...
}: {
  programs.sway = {
    # it will not run on boot
    enable = true;
    extraPackages = with pkgs; [
      foot
      tofi
      wl-clipboard
      grim
      slurp
    ];
  };
  security.polkit.enable = true;

  home-manager.users.dev = {pkgs, ...}: {
    wayland.windowManager.sway = {
      enable = true;
      config = {
        modifier = "Mod4";
        terminal = "foot";
        menu = "tofi";
      };
    };

    home.packages = with pkgs; [
      firefox
    ];
  };
}
