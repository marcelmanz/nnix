{
  config,
  lib,
  pkgs,
  inputs,
  pkgsStable,
  ...
}: let
  homeDir = config.home.homeDirectory;
  clonesOwn = "${homeDir}/clones/own";
in {
  home.stateVersion = "26.05";
  programs.home-manager.enable = true;

  programs.browserpass = {
    enable = true;
  };

  home.packages = with pkgs; [
    flat-remix-icon-theme
    audio-select
    bitwig-studio
    bitwarden-desktop
    gimagereader
    tesseract
    grayjay
    psysonic
    ostui
    simplex-chat-desktop
    strawberry
    ironbar

    audacity
    cinny
    # librewolf # no active commiter in nixpkgs
    jellyfin-desktop
    obsidian
    blesh
    font-awesome
    vikunja-desktop
    abiword
    kdePackages.ark
    brightnessctl
    cliphist
    dejavu_fonts
    nicotine-plus
    dmenu-wayland
    eww
    fira-sans
    foot
    gimp3
    grimblast
    pkgsStable.hyprpaper
    pkgsStable.hyprshot
    kanshi
    keyd
    batsignal
    liberation_ttf
    myna-font
    # mako
    nerd-fonts.blex-mono
    nerd-fonts.droid-sans-mono
    nerd-fonts.iosevka-term
    noto-fonts
    noto-fonts-color-emoji
    nwg-look
    pavucontrol
    pyprland
    qbittorrent
    # radicle-desktop
    ripdrag
    ladybird
    roboto
    roboto-mono
    roboto-serif
    satty
    swayimg
    mqttx
    ultimate-oldschool-pc-font-pack
    (vivaldi.override {
      commandLineArgs = " --enable-features=UseOzonePlatform --ozone-platform=wayland";
    })
    font-manager
    swayosd
    telegram-desktop
    tofi
    bemenu
    j4-dmenu-desktop
    ubuntu-sans-mono
    way-displays
    pkgsStable.waybar
    wf-recorder
    wl-clipboard
    wlr-layout-ui
    wofi-emoji
    # anki
    gelly
    ydotool
    zathura
    penguin-subtitle-player
    unzip
    flameshot
    swappy
    wlprop
    (config.lib.nixGL.wrap quickshell)
    wob
    distrobox
    garamond-libre
    kdePackages.qtdeclarative
    guvcview
    thunderbird
    vvvvvv
    pinentry-all
    libsecret # secret-tool, for the pinentry-rbw keyring lookup
    retrosmart-cursors
    mullvad-browser
    (symlinkJoin {
      name = "signal-desktop-tray";
      paths = [signal-desktop];
      nativeBuildInputs = [makeWrapper];
      postBuild = ''
        wrapProgram $out/bin/signal-desktop --add-flags "--use-tray-icon"
      '';
    })
    socat
    jq
    llama-cpp
    songrec
    picard
    passff-host
    browserpass
  ];

  services.kanshi.enable = true;

  programs.firefox = {
    enable = true;

    profiles.default = {
      path = "default";
      isDefault = true;
      settings."widget.use-xdg-desktop-portal.file-picker" = 1;

      extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
        ublock-origin
        reddit-enhancement-suite
      ];

      # Extensions not available in NUR (install manually):
      # - Vimmatic
      # - Greasemonkey
      # - Redirector
      # - LanguageTool
      # - PassFF
      # - 1Password
      # - TWP - Translate Web Pages
      # - Keep pinned tabs alive
      # - Song id
      # - UnDistracted - Hide Facebook, YouTube Feeds
      # - UltimaDark (theme)
      # - RYS — Remove YouTube Suggestions

      bookmarks = {
        force = true;
        settings = [
          {
            name = "Bookmarks Toolbar";
            toolbar = true;
            bookmarks = [
              {
                name = "marcelarie - Dashboard - Codeberg.org";
                url = "https://codeberg.org/";
              }
              {
                name = "The Rustonomicon";
                url = "https://doc.rust-lang.org/nomicon/index.html";
              }
              {
                name = "Shared-State Concurrency - The Rust Programming Language";
                url = "https://doc.rust-lang.org/book/ch16-03-shared-state.html";
              }
              {
                name = "Better HN";
                url = "https://bhn.vercel.app/top";
              }
              {
                name = "Magnet search";
                url = "https://btdig.com/";
              }
              {
                name = "Sci-Hub: knowledge belongs to all mankind";
                url = "https://sci-hub.st/";
              }
              {
                name = "Opensauced";
                url = "https://app.opensauced.pizza/workspaces/3164341c-c16e-47d9-8cf9-b74220432337";
              }
              {
                name = "Anna's Archive";
                url = "https://annas-archive.org/";
              }
              {
                name = "Bitbucket Issues dashboard";
                url = "https://jira.atlassian.com/projects/BSERV/issues/BSERV-19819?filter=allissues";
              }
              {
                name = "News Minimalist";
                url = "https://www.newsminimalist.com/?sort=significance";
              }
              {
                name = "Browse Standard Ebooks - Standard Ebooks: Free and liberated ebooks, carefully produced for the true book lover";
                url = "https://standardebooks.org/ebooks";
              }
              {
                name = "cmt dev";
                url = "https://cmt-dev.wocs3.com/";
              }
              {
                name = "cmt stg";
                url = "https://cmt-stg.wocs3.com/";
              }
              {
                name = "Marcel Manzanares - Personal";
                url = "https://worldsensing.bamboohr.com/employees/employee.php?id=349&page=2092";
              }
              {
                name = "CMT - 006_ENG/Internal - Google Drive";
                url = "https://drive.google.com/drive/u/1/folders/1aTJz4Omb0QXNUo1WeLrKFR_bMMRUf2q0";
              }
              {
                name = "006_ENG/External - Google Drive";
                url = "https://drive.google.com/drive/u/1/folders/0AOJLFb2bKvUfUk9PVA";
              }
              {
                name = "Desk Booking Tool - Google Sheets";
                url = "https://docs.google.com/spreadsheets/d/1YSfm1OqV_Kel-WQtCuzdLkEne_uThY6rW1CeVEWyLug/edit?gid=808998914#gid=808998914";
              }
              {
                name = "VPN Installation | Guides";
                url = "https://guide.int.worldsensing.com/books/manuals/page/vpn-installation-and-configuration";
              }
              {
                name = "1Password";
                url = "https://worldsensing.1password.eu/signin";
              }
              {
                name = "OpenSearch Dashboards";
                url = "https://opensearch.wocs3.com/app/login?nextUrl=%2Fapp%2Fdiscover#/?_g=%28filters:!%28%29,refreshInterval:%28pause:!t,value:0%29,time:%28from:now-15m,to:now%29%29&_a=%28columns:!%28_source%29,filters:!%28%29,index:dc9292e0-bc12-11ed-a5f8-df7a538a5c2e,interval:auto,query:%28language:kuery,query:%27%27%29,sort:!%28%29%29";
              }
              {
                name = "Worldsensing | Connectivity Management Tool";
                url = "https://cmt-dev.wocs3.com/login";
              }
              {
                name = "Alan Turing - 006_ENG/Internal - Google Drive";
                url = "https://drive.google.com/drive/u/1/folders/1nBsm096yv2hcJdV3NoJYj_-WStxW-KWA";
              }
              {
                name = "Argo CD";
                url = "https://argocd-dev.wocs3.com/login?return_url=https%3A%2F%2Fargocd-dev.wocs3.com%2Fapplications";
              }
              {
                name = "Google Chat";
                url = "https://mail.google.com/chat/u/1/#chat/home";
              }
              {
                name = "Tech Debt Requests";
                url = "https://ws.tpondemand.com/restui/board.aspx?#page=board/4667432318295481078&appConfig=eyJhY2lkIjoiIn0=";
              }
              {
                name = "Work Calendar";
                url = "https://calendar.google.com/calendar/u/1/r/week";
              }
              {
                name = "Component library [CMT Cloud] – Figma";
                url = "https://www.figma.com/design/chpKXzkgKmQCQINNRtohvm/Component-library-%5BCMT-Cloud%5D?node-id=1773-224&t=ynpt3CRPABgMZQSh-0";
              }
              {
                name = "Alan Turing - Team Inventory - Google Sheets";
                url = "https://docs.google.com/spreadsheets/d/14W-ffaFCLPsL1KZYb2OaC4SJSKnmvOtEK_SsMsNfmzg/edit?gid=0#gid=0";
              }
              {
                name = "Postman WS Workspace";
                url = "https://web.postman.co/workspace/5c7a1002-0b1c-43fe-82fd-5fc18ed1ef63/request/41010325-5fc76bb5-24f8-4704-9522-fdc66e0cb6ac";
              }
              {
                name = "CMT.drawio - draw.io";
                url = "https://app.diagrams.net/#G1krBRlaHvGF7gaEQ8ShMSpJeB2YpB_gIg#%7B%22pageId%22%3A%22Njqf2apxFuwAC4SVHstD%22%7D";
              }
              {
                name = "Keycloak Administration Console";
                url = "https://keycloak-dev.wocs3.com/admin/master/console/";
              }
              {
                name = "92760 Hide/DIsable Integration Creation and Visibility for Account Admins - Google Docs";
                url = "https://docs.google.com/document/d/1s4vl_41iCarTXBRgcW2jezwjcMgyjycgQvPE4v9zONw/edit?tab=t.0";
              }
              {
                name = "CMT Cloud How-To / Support - Google Docs";
                url = "https://docs.google.com/document/d/1m18P6bPIX9aiusiom-J-GDEiqOuzPQANb6IYCDHh1lo/edit?tab=t.0";
              }
              {
                name = "ThingsBoard | Home";
                url = "https://thingsboard-dev.wocs3.com/home";
              }
              {
                name = "WS Snippets — Bitbucket";
                url = "https://bitbucket.org/worldsensing_traffic/workspace/snippets/";
              }
              {
                name = "Goku M3 - Web - Front end";
                url = "https://ws.tpondemand.com/restui/board.aspx?#page=feature/99189";
              }
              {
                name = "ThreadX4 internal API - Google Docs";
                url = "https://docs.google.com/document/d/1DtttiaXcZogKqotNqtJAKeR2cOuzK9ERwDy2QM3WdyU/edit?tab=t.efmodvkivcyt";
              }
            ];
          }
        ];
      };

      search = {
        default = "Kagi";
        force = true;
        engines = {
          "Kagi" = {
            urls = [
              {
                template = "https://kagi.com/search";
                params = [
                  {
                    name = "q";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];
            definedAliases = ["@k"];
          };
        };
      };

      settings = {
        # UI/UX Settings
        "ui.key.menuAccessKeyFocuses" = false;
        "general.autoScroll" = true;
        "intl.accept_languages" = "en-us,en,es-es";
        "accessibility.typeaheadfind.flashBar" = 0;
        "browser.download.autohideButton" = false;

        # About Config
        "browser.aboutConfig.showWarning" = false;

        # Bookmarks
        "browser.bookmarks.showMobileBookmarks" = true;

        # Discovery/Suggestions
        "browser.discovery.enabled" = false;

        # New Tab Page
        "browser.newtabpage.activity-stream.feeds.topsites" = false;
        "browser.newtabpage.activity-stream.showSearch" = false;
        "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
        "browser.newtabpage.activity-stream.newtabWallpapers.wallpaper" = "solid-color-picker-#1e1e1e";

        # Safe Browsing
        "browser.safebrowsing.downloads.remote.block_potentially_unwanted" = false;

        # Startup
        "browser.startup.homepage" = "https://kagi.com";
        "browser.startup.page" = 3;

        # Theme
        "browser.theme.toolbar-theme" = 0;
        "extensions.activeThemeID" = "{f2b832a9-f0f5-4532-934c-74b25eb23fb9}";

        # URL Bar
        "browser.urlbar.showSearchSuggestionsFirst" = false;
        "browser.urlbar.suggest.engines" = false;

        # Media
        "media.eme.enabled" = true;
        "media.videocontrols.picture-in-picture.video-toggle.enabled" = false;

        # Network/Privacy
        "network.dns.disablePrefetch" = true;
        "network.http.speculative-parallel-limit" = 0;
        "network.prefetch-next" = false;

        # Privacy
        "privacy.clearOnShutdown_v2.formdata" = true;

        # Containers
        "privacy.userContext.enabled" = true;
        "privacy.userContext.ui.enabled" = true;

        # Passwords
        "signon.rememberSignons" = false;

        # UserChrome
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

        # Vertical Tabs Configuration
        "sidebar.verticalTabs" = true;
        "sidebar.revamp" = true;
        "sidebar.visibility" = "hide-sidebar";
        "sidebar.main.tools" = "syncedtabs,history,bookmarks";
        "browser.toolbarbuttons.introduced.sidebar-button" = true;
        "browser.engagement.sidebar-button.has-used" = true;
        "sidebar.new-sidebar.has-used" = true;
        "sidebar.old-sidebar.has-used" = true;
        "sidebar.verticalTabs.dragToPinPromo.dismissed" = true;
      };

      #       userChrome = ''
      # #TabsToolbar,
      # #toolbar-menubar,
      # #PersonalToolbar,
      # #titlebar {
      #   visibility: collapse !important;
      # }
      #
      # #navigator-toolbox {
      #   position: relative;
      # }
      #
      # #nav-bar {
      #   margin-top: -40px !important;
      #   opacity: 0;
      #   z-index: 1;
      #   transition:
      #     margin-top 0.2s ease,
      #     opacity 0.2s ease !important;
      # }
      #
      # #navigator-toolbox:focus-within #nav-bar {
      #   margin-top: 0 !important;
      #   opacity: 1 !important;
      # }
      #       '';
    };
  };

  xdg.configFile."mimeapps.list".force = true;

  xdg.dataFile."dbus-1/services/org.freedesktop.Notifications.service".text = ''
    [D-BUS Service]
    Name=org.freedesktop.Notifications
    Exec=${config.lib.nixGL.wrap pkgs.quickshell}/bin/qs -p ${config.xdg.configHome}/quickshell/notifications --no-duplicate
  '';

  # Plasma's Dolphin also claims this name; user service files take precedence over system ones
  xdg.dataFile."dbus-1/services/org.freedesktop.FileManager1.service".text = let
    nnn-filemanager1 =
      pkgs.writers.writePython3Bin "nnn-filemanager1" {
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

  xdg.desktopEntries.nnn-foot = {
    name = "nnn";
    exec = "foot -a nnn nnn %f";
    mimeType = ["inode/directory"];
  };

  xdg.mimeApps = let
    defaultApplications = {
      "text/plain" = ["nvim.desktop"];
      "text/markdown" = ["nvim.desktop"];
      "text/html" = ["nvim.desktop"];
      "application/json" = ["nvim.desktop"];
      "text/csv" = ["csvlens.desktop"];
      "text/comma-separated-values" = ["csvlens.desktop"];
      "application/vnd.oasis.opendocument.text" = ["nvim.desktop"];

      # Web browser scheme handlers
      "x-scheme-handler/http" = ["brave-origin-nightly.desktop"];
      "x-scheme-handler/https" = ["brave-origin-nightly.desktop"];

      # Brave-Origin per-container scheme handlers (registerProtocolHandler).
      # force-managed mimeapps.list wipes Brave's runtime registration, so map
      # each container UUID back to Brave here. Add a line per new container.

      "image/png" = ["imv.desktop"];
      "image/jpeg" = ["imv.desktop"];
      "image/jpg" = ["imv.desktop"];
      "image/gif" = ["imv.desktop"];
      "image/webp" = ["imv.desktop"];
      "image/tiff" = ["imv.desktop"];
      "image/bmp" = ["imv.desktop"];
      "image/svg+xml" = ["imv.desktop"];
      "image/avif" = ["imv.desktop"];
      "image/heif" = ["imv.desktop"];
      "image/heic" = ["imv.desktop"];

      "application/pdf" = [
        "zathura.desktop"
        "org.pwmt.zathura-pdf-mupdf.desktop"
      ];

      # Video
      "video/mp4" = ["mpv.desktop"];
      "video/x-matroska" = ["mpv.desktop"];
      "video/webm" = ["mpv.desktop"];
      "video/x-msvideo" = ["mpv.desktop"];
      "video/quicktime" = ["mpv.desktop"];

      # Audio
      "audio/mpeg" = ["mpv.desktop"];
      "audio/flac" = ["mpv.desktop"];
      "audio/ogg" = ["mpv.desktop"];
      "audio/wav" = ["mpv.desktop"];
      "audio/x-wav" = ["mpv.desktop"];
      "audio/aac" = ["mpv.desktop"];

      # Code files
      "text/x-python" = ["nvim.desktop"];
      "text/x-shellscript" = ["nvim.desktop"];
      "text/x-yaml" = ["nvim.desktop"];
      "application/x-yaml" = ["nvim.desktop"];
      "text/x-toml" = ["nvim.desktop"];
      "application/toml" = ["nvim.desktop"];
      "text/javascript" = ["nvim.desktop"];
      "application/javascript" = ["nvim.desktop"];
      "application/typescript" = ["nvim.desktop"];
      "text/x-rust" = ["nvim.desktop"];
      "text/x-c" = ["nvim.desktop"];
      "text/x-c++" = ["nvim.desktop"];
      "text/x-go" = ["nvim.desktop"];
      "application/xml" = ["nvim.desktop"];
      "text/xml" = ["nvim.desktop"];

      # Archives
      "application/zip" = ["org.kde.ark.desktop"];
      "application/x-tar" = ["org.kde.ark.desktop"];
      "application/x-bzip" = ["org.kde.ark.desktop"];
      "application/x-xz" = ["org.kde.ark.desktop"];
      "application/gzip" = ["org.kde.ark.desktop"];
      "application/x-7z-compressed" = ["org.kde.ark.desktop"];
      "application/x-compressed-tar" = ["org.kde.ark.desktop"];

      # Other
      "application/epub+zip" = ["org.pwmt.zathura-pdf-mupdf.desktop"];
      "application/x-bittorrent" = ["org.qbittorrent.qBittorrent.desktop"];
      "inode/directory" = ["nnn-open.desktop"];
    };
  in {
    enable = true;
    inherit defaultApplications;
    associations = {
      added =
        defaultApplications
        // {
          "text/json" = ["nvim.desktop"];
        };
      removed = {
        "image/png" = [
          "gimp.desktop"
          "chromium-browser.desktop"
        ];
        "image/jpeg" = ["gimp.desktop"];
        "image/jpg" = ["gimp.desktop"];
        "image/gif" = ["gimp.desktop"];
        "image/webp" = ["gimp.desktop"];
        "image/tiff" = ["gimp.desktop"];
        "image/bmp" = ["gimp.desktop"];
        "image/svg+xml" = ["gimp.desktop"];
        "image/avif" = ["gimp.desktop"];
        "image/heif" = ["gimp.desktop"];
        "image/heic" = ["gimp.desktop"];
      };
    };
  };

  home.file = let
    link = config.lib.file.mkOutOfStoreSymlink;
    dots = "${clonesOwn}/dots";
  in {
    # GUI-specific config files only
    ".config/hypr/hyprland.lua".source = link "${dots}/.config/hypr/hyprland.lua";
    # device.lua is required by hyprland.lua; resolve it statically per host (was a runtime exec-once symlink)
    ".config/hypr/device.lua".source = lib.mkDefault (link "${dots}/.config/hypr/devices/nixos.lua");
    ".config/hypr/hypridle.conf".source = link "${dots}/.config/hypr/hypridle.conf";
    ".config/hypr/hyprlock.conf".source = link "${dots}/.config/hypr/hyprlock.conf";
    ".config/hypr/hyprpaper.conf".source = link "${dots}/.config/hypr/hyprpaper.conf";
    ".config/hypr/keybinds.lua".source = link "${dots}/.config/hypr/keybinds.lua";
    ".config/hypr/layouts.lua".source = link "${dots}/.config/hypr/layouts.lua";
    ".config/hypr/monitors.conf".source = link "${dots}/.config/hypr/monitors.conf";
    ".config/pypr/config.toml".source = link "${dots}/.config/pypr/config.toml";
    ".config/hypr/workspaces.conf".source = link "${dots}/.config/hypr/workspaces.conf";
    ".config/foot/foot.ini" = {
      source = link "${dots}/.config/foot/foot.ini";
      force = true;
    };
    ".config/foot/colors-dark.ini".source = link "${dots}/.config/foot/colors-dark.ini";
    ".config/foot/colors-light.ini".source = link "${dots}/.config/foot/colors-light.ini";
    ".config/foot/set-font".source = link "${dots}/.config/foot/set-font";
    ".config/foot/set-theme".source = link "${dots}/.config/foot/set-theme";
    ".config/foot/themes.d" = {
      source = link "${dots}/.config/foot/themes.d";
      recursive = true;
    };
    ".config/tofi/config".source = link "${dots}/.config/tofi/config";
    ".config/swappy/config".source = link "${dots}/.config/swappy/config";
    # ".config/mako/config".source = link "${dots}/.config/mako/config";
    ".config/ironbar/config.toml".source = link "${dots}/.config/ironbar/config.toml";
    ".config/ostui/config".source = link "${dots}/.config/ostui/config";

    # Firefox extension configs
    ".config/vimmatic/vimmatic.json".source = link "${dots}/.config/vimmatic/vimmatic.json";

    # GUI-specific directories
    ".config/waybar" = {
      source = link "${dots}/.config/waybar";
      recursive = true;
    };

    ".config/quickshell" = {
      source = link "${dots}/.config/quickshell";
      recursive = true;
    };

    ".config/alacritty" = {
      source = link "${dots}/.config/alacritty";
      recursive = true;
    };

    ".config/eww" = {
      source = link "${dots}/.config/eww";
      recursive = true;
    };

    # ".config/borders" = {
    #   source = link "${dots}/.config/borders";
    #   recursive = true;
    # };

    ".config/wob" = {
      source = link "${dots}/.config/wob";
      recursive = true;
    };

    # ".config/swaync/config.json".source = link "${dots}/.config/swaync/config.json";

    ".config/BraveSoftware/Brave-Origin-Beta/NativeMessagingHosts/com.github.browserpass.native.json".source = "${pkgs.browserpass}/lib/browserpass/hosts/chromium/com.github.browserpass.native.json";

    ".config/BraveSoftware/Brave-Origin-Nightly/NativeMessagingHosts/com.github.browserpass.native.json".source = "${pkgs.browserpass}/lib/browserpass/hosts/chromium/com.github.browserpass.native.json";

    ".local/share/applications/csvlens.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=csvlens
      Comment=CSV file viewer
      Exec=kitty --hold csvlens %f
      Terminal=false
      MimeType=text/csv;text/comma-separated-values;
      Categories=Utility;Viewer;
      NoDisplay=false
    '';

    # jellyfin-desktop is Qt6 Wayland-native; global QT_SCALE_FACTOR=2 is meant for XWayland Qt under force_zero_scaling and makes Wayland-native Qt render ~2x too big.
    # Override to 1 here so the compositor scale alone sizes it. force=true tolerates the live symlink until next switch.
    ".local/share/applications/org.jellyfin.JellyfinDesktop.desktop" = {
      source = link "${dots}/.local/share/applications/org.jellyfin.JellyfinDesktop.desktop";
      force = true;
    };
  };
}
