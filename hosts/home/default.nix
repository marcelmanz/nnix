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
  home.sessionVariables.NIX_REMOTE = "ssh-ng://mlab";
  imports = [
    ../../home/terminal.nix
    ../../home/gui.nix
    ../../home/i3.nix
    ../../home/bandcamp-cookies.nix
    ../../home/syncthing.nix
  ];

  # Route the portal Settings interface to the GTK backend so Brave/Chromium's read it live
  xdg.configFile."xdg-desktop-portal/hyprland-portals.conf".text = ''
    [preferred]
    default=gtk;hyprland
    org.freedesktop.impl.portal.ScreenCast=hyprland
    org.freedesktop.impl.portal.Screenshot=hyprland
    org.freedesktop.impl.portal.Settings=gtk
    org.freedesktop.impl.portal.FileChooser=termfilechooser
  '';
  xdg.configFile."xdg-desktop-portal-termfilechooser/config".text = ''
    [filechooser]
    cmd=${pkgs.xdg-desktop-portal-termfilechooser}/share/xdg-desktop-portal-termfilechooser/nnn-wrapper.sh
    default_dir=$HOME
    env=TERMCMD=foot -a termfilechooser
  '';
  # Plasma's Dolphin also claims this name; user service files take precedence over system ones
  xdg.dataFile."dbus-1/services/org.freedesktop.FileManager1.service".text = let
    nnn-filemanager1 = pkgs.writers.writePython3Bin "nnn-filemanager1" {
      libraries = [pkgs.python3Packages.dbus-next];
      flakeIgnore = ["F722" "F821" "E501"];
    } ''
      import asyncio
      import subprocess
      from urllib.parse import unquote, urlparse
      from dbus_next.aio import MessageBus
      from dbus_next.service import ServiceInterface, method


      def open_in_nnn(uris):
          for uri in uris:
              subprocess.Popen(["${pkgs.foot}/bin/foot", "-a", "nnn", "${pkgs.nnn}/bin/nnn", unquote(urlparse(uri).path)])


      class FileManager1(ServiceInterface):
          def __init__(self):
              super().__init__("org.freedesktop.FileManager1")

          @method()
          def ShowFolders(self, uris: "as", startup_id: "s"):
              open_in_nnn(uris)

          @method()
          def ShowItems(self, uris: "as", startup_id: "s"):
              open_in_nnn(uris)

          @method()
          def ShowItemProperties(self, uris: "as", startup_id: "s"):
              open_in_nnn(uris)


      async def main():
          bus = await MessageBus().connect()
          bus.export("/org/freedesktop/FileManager1", FileManager1())
          await bus.request_name("org.freedesktop.FileManager1")
          await asyncio.Event().wait()


      asyncio.run(main())
    '';
  in ''
    [D-BUS Service]
    Name=org.freedesktop.FileManager1
    Exec=${nnn-filemanager1}/bin/nnn-filemanager1
  '';

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
    _1password-cli
    cinny-desktop
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
    ".config/hypr/devices/nixos.lua".source = link "${dots}/.config/hypr/devices/nixos.lua";
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
