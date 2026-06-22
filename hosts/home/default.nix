{
  config,
  pkgs,
  pkgsStable,
  nixGL,
  ...
}: let
  homeDir = "/home/marcel";
in {
  home.username = "marcel";
  home.homeDirectory = homeDir;
  imports = [
    ../../home/terminal.nix
    ../../home/gui.nix
  ];

  # nixGL = {
  #   packages = nixGL.packages;
  #   defaultWrapper = "mesa";
  # };

  home.packages = with pkgs; [
    element-desktop
    (config.lib.nixGL.wrap mixxx)
    # ungoogled-chromium
    # zeroad
    # stremio
    pkgsStable.hyprlock
    pkgsStable.hyprland-qtutils
    alacritty
    neovide
    xdg-desktop-portal-hyprland
    grim
    slurp
    telegram-desktop
    imv
    alsa-utils
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    aonsoku
    (pkgs.writeShellScriptBin "vivaldi-stable" ''
      exec -a "$0" ${pkgs.vivaldi}/bin/vivaldi-stable --ozone-platform-hint=wayland --enable-features=WaylandWindowDecorations "$@"
    '')
  ];

  programs.mpv = {
    enable = true;
    package = pkgsStable.mpv;
    # scripts = [pkgsStable.mpvScripts.mpris];
  };

  home.file = let
    link = config.lib.file.mkOutOfStoreSymlink;
    clonesOwn = "${homeDir}/clones/own";
    dots = "${clonesOwn}/dots";
  in {
    ".config/kanshi/config".source = link "${dots}/.config/kanshi/config";
    ".config/hypr/devices/nixos.conf".source = link "${dots}/.config/hypr/devices/nixos.conf";
    ".local/share/applications/brave-origin-nightly.desktop".text = ''
      [Desktop Entry]
      Version=1.0
      Name=Brave Origin (nightly)
      GenericName=Web Browser
      Comment=Access the Internet
      Exec=brave-origin-nightly --password-store=gnome-libsecret %U
      StartupNotify=true
      Terminal=false
      Icon=brave-origin-nightly
      Type=Application
      Categories=Network;WebBrowser;
      MimeType=application/pdf;application/rdf+xml;application/rss+xml;application/xhtml+xml;application/xhtml_xml;application/xml;image/gif;image/jpeg;image/png;image/webp;text/html;text/xml;x-scheme-handler/http;x-scheme-handler/https;x-scheme-handler/chromium;
      Actions=new-window;new-private-window;

      [Desktop Action new-window]
      Name=New Window
      Exec=brave-origin-nightly --password-store=gnome-libsecret

      [Desktop Action new-private-window]
      Name=New Incognito Window
      Exec=brave-origin-nightly --password-store=gnome-libsecret --incognito
    '';
  };
}
