{
  _config,
  pkgs,
  _lib,
  ...
}: let
  # Myna: github.com/sayyadirfanali/Myna
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
}
