{
  config,
  pkgs,
  inputs,
  pkgsStable,
  ...
}: let
  homeDir = config.home.homeDirectory;
  clonesOwn = "${homeDir}/clones/own";
  pstore = "${clonesOwn}/password-store";
in {
  home.stateVersion = "26.05";
  programs.home-manager.enable = true;

  programs.browserpass = {
    enable = true;
    browsers = ["brave"];
  };

  home.packages = with pkgs; [
    audio-select
    gimagereader
    tesseract
    grayjay
    orion
    brave
    librewolf
    jellyfin-desktop
    obsidian
    blesh
    # winetricks  # disabled: openal-soft/pipewire linking failure in current nixpkgs
    font-awesome
    abiword
    kdePackages.ark
    brightnessctl
    cliphist
    dejavu_fonts
    nicotine-plus
    dmenu-wayland
    eww
    fira-sans
    font-awesome
    foot
    jitsi
    gimp3
    grimblast
    pkgsStable.hyprpaper
    pkgsStable.hyprshot
    kanshi
    keyd
    batsignal
    liberation_ttf
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
    roboto
    roboto-mono
    roboto-serif
    # rustdesk
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
    ubuntu-sans-mono
    way-displays
    pkgsStable.waybar
    wf-recorder
    wl-clipboard
    wlr-layout-ui
    wofi-emoji
    ydotool
    zathura
    penguin-subtitle-player
    unzip
    flameshot
    swappy
    wlprop
    # rustdesk
    quickshell
    wob
    # ironbar # currently returns an error releated to libedev
    distrobox
    garamond-libre
    kdePackages.qtdeclarative
    guvcview
    thunderbird
    wlprop
    # wine  # disabled: openal-soft/pipewire linking failure in current nixpkgs
    vvvvvv
    pinentry-all
    mullvad-browser
    signal-desktop
    # open-webui
    socat
    jq
    llama-cpp
    songrec
    picard
  ];

  services.swaync = {
    enable = true;
    settings = {
      positionX = "right";
      positionY = "top";

      control-center-margin-top = 2;
      control-center-margin-bottom = 2;
      control-center-margin-right = 1;
      control-center-margin-left = 0;

      notification-icon-size = 48;
      notification-body-image-height = 160;
      notification-body-image-width = 90;

      timeout = 6;
      timeout-low = 4;
      timeout-critical = 0;

      fit-to-screen = true;

      control-center-width = 380;
      notification-window-width = 366;

      keyboard-shortcuts = true;
      image-visibility = "when-available";

      transition-time = 100;

      hide-on-clear = false;
      hide-on-action = true;

      script-fail-notify = true;

      scripts = {
        example-script = {
          exec = "echo 'Do something...'";
          urgency = "Normal";
        };
      };

      notification-visibility = {
        example-name = {
          state = "muted";
          urgency = "Low";
          app-name = "Spotify";
        };
      };

      widgets = [
        "label"
        "menubar"
        "buttons-grid"
        "volume"
        "mpris"
        "title"
        "dnd"
        "notifications"
      ];

      widget-config = {
        title = {
          text = "Notifications";
          clear-all-button = true;
          button-text = "Clear All";
        };

        dnd = {
          text = "Do Not Disturb";
        };

        label = {
          max-lines = 1;
          text = "Controll Center";
        };

        mpris = {
          image-size = 96;
          image-radius = 6;
        };

        backlight = {
          label = "";
          device = "intel_backlight";
          min = 10;
        };

        "backlight#KB" = {
          label = " ";
          device = "asus::kbd_backlight";
          subsystem = "leds";
        };

        volume = {
          label = "";
        };

        menubar = {
          "menu#power-buttons" = {
            label = "";
            position = "right";
            actions = [
              {
                label = "   Reboot";
                command = "systemctl reboot";
              }
              {
                label = "   Lock";
                command = "swaylock.sh";
              }
              {
                label = "   Logout";
                command = "loginctl terminate-session \${XDG_SESSION_ID-}";
              }
              {
                label = "   Shut down";
                command = "systemctl poweroff";
              }
            ];
          };

          "menu#powermode-buttons" = {
            label = "";
            position = "right";
            actions = [
              {
                label = "Performance";
                command = "powerprofilesctl set performance";
              }
              {
                label = "Balanced";
                command = "powerprofilesctl set balanced";
              }
              {
                label = "Power-saver";
                command = "powerprofilesctl set power-saver";
              }
            ];
          };

          "menu#screenshot-buttons" = {
            label = "";
            position = "left";
            actions = [
              {
                label = "   Entire screen";
                command = "swaync-client -cp && sleep 1 && hyprshot -m output";
              }
              {
                label = "   Select a region";
                command = "swaync-client -cp && sleep 1 && hyprshot -m region";
              }
              {
                label = "   Open screenshot menu";
                command = "swaync-client -cp && rofi-screenshot";
              }
              {
                label = "   Open screenshot folder";
                command = "exo-open $HYPRSHOT_DIR";
              }
            ];
          };

          "menu#screencast-buttons" = {
            label = "";
            position = "left";
            actions = [
              {
                label = "   Entire screen";
                command = "swaync-client -cp && sleep 1 && recording.sh toggle fullscreen";
              }
              {
                label = "   Select a region";
                command = "swaync-client -cp && sleep 1 && recording.sh toggle region";
              }
              {
                label = "   Stop";
                command = "swaync-client -cp && recording.sh stop";
              }
              {
                label = "   Open screencast folder";
                command = "$XDG_VIDEOS_DIR/Screencasts";
              }
            ];
          };
        };

        buttons-grid = {
          actions = [
            {
              label = "";
              command = "nm-connection-editor";
            }
            {
              label = "";
              command = "blueman";
            }
            {
              label = "";
              command = "nwg-look";
            }
            {
              label = "";
              command = "exo-open ~/ConfigHub";
            }
            {
              label = "";
              command = "ymuse";
            }
            {
              label = "";
              command = "orage";
            }
            {
              label = "";
              command = "pamac-manager";
            }
            {
              label = "";
              command = "firefox";
            }
          ];
        };
      };
    };
    style = ''
      @define-color noti-border-color rgba(255, 255, 255, 0.15);
      @define-color noti-bg rgba(51,51,51,1);
      @define-color noti-bg-hover-alt #454545;
      @define-color noti-bg-alt rgba(43,43,43,1);
      @define-color noti-fg white;
      @define-color noti-bg-hover rgba(255, 255, 255, 0);
      @define-color noti-bg-focus rgba(255, 255, 255, 0);
      @define-color noti-close-bg rgba(255, 255, 255, 0);
      @define-color noti-close-bg-hover rgba(255, 255, 255, 0);
      @define-color noti-urgent rgba(255,0,80,0.8);
      @define-color bg-selected #33ccff;

      *{
        font-family: FontAwesome, "Noto Sans";
        color: @noti-fg;
      }

      .notification-row {
        outline: none;
      }

      .notification-row:focus,
      .notification-row:hover {
        background: @noti-bg-focus;
      }

      .notification {
        border: 1px solid @bg-selected;
        border-radius: 4px;
        margin: 6px 12px;
        box-shadow: none;
        padding: 0;
      }

      /* Uncomment to enable specific urgency colors */
      /* .low {
        background: yellow;
      }

      .normal {
        background: green;
      } */

      .critical {
        border: 1px solid @noti-urgent;
      }


      .notification-content {
        background: transparent;
        padding: 6px;
        border-radius: 4px;
      }

      .close-button {
        background: @noti-close-bg;
        color: white;
        text-shadow: none;
        padding: 0;
        border-radius: 100%;
        margin-top: 10px;
        margin-right: 16px;
        box-shadow: none;
        border: none;
        min-width: 24px;
        min-height: 24px;
      }

      .close-button:hover {
        box-shadow: none;
        background: @noti-close-bg-hover;
        transition: all 0.15s ease-in-out;
        border: none;
      }

      .notification-default-action,
      .notification-action {
        padding: 4px;
        margin: 0;
        box-shadow: none;
        background: @noti-bg;
        border: 1px solid @noti-border-color;
        color: white;
      }

      .notification-default-action:hover,
      .notification-action:hover {
        -gtk-icon-effect: none;
        background: @noti-bg-alt;
      }

      .notification-default-action {
        border-radius: 4px;
      }

      /* When alternative actions are visible */
      .notification-default-action:not(:only-child) {
        border-bottom-left-radius: 0px;
        border-bottom-right-radius: 0px;
      }

      .notification-action {
        border-radius: 0px;
        border-top: none;
        border-right: none;
      }

      /* add bottom border radius to eliminate clipping */
      .notification-action:first-child {
        border-bottom-left-radius: 4px;
      }

      .notification-action:last-child {
        border-bottom-right-radius: 4px;
        border-right: 1px solid @noti-border-color;
      }

      .image {}

      .body-image {
        margin-top: 6px;
        background-color: white;
        border-radius: 6px;
      }

      .summary {
        font-size: 14px;
        font-weight: bold;
        background: transparent;
        color: white;
        text-shadow: none;
      }

      .time {
        font-size: 13px;
        font-weight: bold;
        background: transparent;
        color: white;
        text-shadow: none;
        margin-right: 18px;
      }

      .body {
        font-size: 12px;
        font-weight: normal;
        background: transparent;
        color: white;
        text-shadow: none;
      }

      /* The "Notifications" and "Do Not Disturb" text widget */
      .top-action-title {
        color: white;
        text-shadow: none;
      }

      .control-center {
        background-color: @noti-bg-alt;
        border-radius: 6px;
        border: 1px solid @bg-selected;
      }

      .control-center-list {
        background: transparent;
      }

      .floating-notifications {
        background: transparent;
      }

      /* Window behind control center and on all other monitors */
      .blank-window {
        background: transparent;
      }

      /*** Widgets ***/

      /* Title widget */
      .widget-title {
        margin: 8px;
        font-size: 16px;
      }

      .widget-title>button {
        font-size: initial;
        color: white;
        text-shadow: none;
        background: @noti-bg;
        border: 1px solid @noti-border-color;
        box-shadow: none;
        border-radius: 4px;
      }

      .widget-title>button:hover {
        background: @noti-bg-hover;
      }

      /* DND widget */
      .widget-dnd {
        margin: 8px;
        font-size: 1.1rem;
      }

      .widget-dnd>switch {
        font-size: initial;
        border-radius: 4px;
        background: @noti-bg;
        border: 1px solid @noti-border-color;
        box-shadow: none;
      }

      .widget-dnd>switch:checked {
        background: @bg-selected;
      }

      .widget-dnd>switch slider {
        background: @noti-bg-hover;
        border-radius: 4px;
      }

      /* Label widget */
      .widget-label {
        margin: 4px 8px 8px;
      }

      .widget-label>label {
        font-size: 16px;
      }

      /* Mpris widget */
      .widget-mpris {
        /* The parent to all players */
      }

      .widget-mpris-player {
        padding: 8px;
        margin: 8px;
      }

      .widget-mpris-title {
        font-weight: bold;
        font-size: 1.25rem;
      }

      .widget-mpris-subtitle {
        font-size: 1.1rem;
      }

      /* Volume and Brightness Widget*/

      .widget-volume {
        background-color: @noti-bg;
        padding: 4px 4px 4px 20px;
        margin: 0px 8px 8px 8px;
        border-radius: 4px;
        font-size: 14px;
      }

      .widget-backlight {
        background-color: @noti-bg;
        padding: 8px 8px 4px 8px;
        margin: 8px 8px 0px 8px;
        border-top-left-radius: 12px;
        border-top-right-radius: 12px;
      }

      .KB {
        padding: 4px 8px 4px 8px;
        margin: 0px 8px 0px 8px;
        border-radius: 0;
      }

      .widget-menubar>box{
        padding: 8px 0px 4px;
        margin: 0px 8px;
        border-radius: 4px 4px 0px 0px;
        background-color: @noti-bg;
      }

      .widget-menubar>box>.menu-button-bar>button{
        border: 1px solid @noti-border-color;
        background: @noti-bg;
        border-radius: 4px;
        margin: 4px 12px;
      }

      .widget-buttons-grid{
        padding: 0px 8px 8px;
        margin: 0px 8px 8px;
        border-radius: 0px 0px 4px 4px;
        background-color: @noti-bg;
        font-size: 14px;
      }

      .widget-buttons-grid>flowbox>flowboxchild>button{
        background: @noti-bg;
        border-radius: 4px;
      }

      .widget-buttons-grid>flowbox>flowboxchild>button:hover {
        background: @noti-bg-hover;
      }

      .screenshot-buttons,
      .screencast-buttons,
      .powermode-buttons,
      .power-buttons{
        border-radius: 4px;
      }

      .screenshot-buttons>button,
      .screencast-buttons>button,
      .powermode-buttons>button,
      .power-buttons>button{
        background: transparent;
        padding: 2px 0px;
        margin: 5px 70px 3px;
        border: 1px solid @noti-border-color;
      }

      .screenshot-buttons>button:hover,
      .screencast-buttons>button:hover,
      .powermode-buttons>button:hover,
      .power-buttons>button:hover{
        background: @noti-bg-hover;
      }
    '';
  };

  programs.firefox = {
    enable = true;

    profiles.default = {
      path = "default";
      isDefault = true;

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

        # UI Customization State (Vertical Tabs Layout)
        # This captures your current layout with tabs on the side
        "browser.uiCustomization.state" = ''{"placements":{"widget-overflow-fixed-list":[],"unified-extensions-area":["search_kagi_com-browser-action"],"nav-bar":["sidebar-button","back-button","forward-button","stop-reload-button","vertical-spacer","urlbar-container","downloads-button","fxa-toolbar-menu-button","unified-extensions-button","ublock0_raymondhill_net-browser-action","vimmatic_i-beam_org-browser-action","passff_invicem_pro-browser-action","languagetool-webextension_languagetool_org-browser-action","redirector_einaregilsson_com-browser-action","harper_writewithharper_com-browser-action"],"toolbar-menubar":["menubar-items"],"TabsToolbar":[],"vertical-tabs":["tabbrowser-tabs"],"PersonalToolbar":["import-button","personal-bookmarks"]},"seen":["developer-button","screenshot-button","vimmatic_i-beam_org-browser-action","search_kagi_com-browser-action","ublock0_raymondhill_net-browser-action","passff_invicem_pro-browser-action","languagetool-webextension_languagetool_org-browser-action","redirector_einaregilsson_com-browser-action","harper_writewithharper_com-browser-action"],"dirtyAreaCache":["nav-bar","vertical-tabs","toolbar-menubar","TabsToolbar","PersonalToolbar","unified-extensions-area","widget-overflow-fixed-list"],"currentVersion":23,"newElementCount":8}'';

        # Backup of horizontal tabs layout (in case you want to switch back)
        "browser.uiCustomization.horizontalTabsBackup" = ''{"placements":{"widget-overflow-fixed-list":[],"unified-extensions-area":["vimmatic_i-beam_org-browser-action","search_kagi_com-browser-action"],"nav-bar":["sidebar-button","back-button","forward-button","stop-reload-button","customizableui-special-spring1","vertical-spacer","urlbar-container","customizableui-special-spring2","downloads-button","fxa-toolbar-menu-button","unified-extensions-button","ublock0_raymondhill_net-browser-action"],"toolbar-menubar":["menubar-items"],"TabsToolbar":["firefox-view-button","tabbrowser-tabs","new-tab-button","alltabs-button"],"vertical-tabs":[],"PersonalToolbar":["import-button","personal-bookmarks"]},"seen":["developer-button","screenshot-button","vimmatic_i-beam_org-browser-action","search_kagi_com-browser-action","ublock0_raymondhill_net-browser-action"],"dirtyAreaCache":["nav-bar","vertical-tabs","toolbar-menubar","TabsToolbar","PersonalToolbar","unified-extensions-area"],"currentVersion":23,"newElementCount":2}'';

        "browser.uiCustomization.navBarWhenVerticalTabs" = ''["sidebar-button","back-button","forward-button","stop-reload-button","customizableui-special-spring1","vertical-spacer","urlbar-container","customizableui-special-spring2","downloads-button","fxa-toolbar-menu-button","unified-extensions-button","ublock0_raymondhill_net-browser-action","vimmatic_i-beam_org-browser-action"]'';
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

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
    OPENSSL_DIR = "${pkgs.openssl.out}";
    OPENSSL_LIB_DIR = "${pkgs.openssl.out}/lib";
    OPENSSL_INCLUDE_DIR = "${pkgs.openssl.dev}/include";
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/plain" = ["nvim.desktop"];
      "text/markdown" = ["nvim.desktop"];
      "text/html" = ["nvim.desktop"];
      "application/json" = ["nvim.desktop"];
      "text/csv" = ["csvlens.desktop"];
      "text/comma-separated-values" = ["csvlens.desktop"];
      "application/vnd.oasis.opendocument.text" = ["nvim.desktop"];

      # Web browser scheme handlers
      "x-scheme-handler/http" = ["brave-origin.desktop"];
      "x-scheme-handler/https" = ["brave-origin.desktop"];
      "x-scheme-handler/about" = ["brave-origin.desktop"];
      "x-scheme-handler/unknown" = ["brave-origin.desktop"];

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
      "inode/directory" = ["kitty-open.desktop"];
    };
    associations = {
      added = {
        "text/plain" = ["nvim.desktop"];
        "text/markdown" = ["nvim.desktop"];
        "text/json" = ["nvim.desktop"];
        "application/json" = ["nvim.desktop"];
        "text/csv" = ["csvlens.desktop"];
        "text/comma-separated-values" = ["csvlens.desktop"];
        "application/vnd.oasis.opendocument.text" = ["nvim.desktop"];

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

        "application/pdf" = ["org.pwmt.zathura-pdf-mupdf.desktop"];

        "video/mp4" = ["mpv.desktop"];
        "video/x-matroska" = ["mpv.desktop"];
        "video/webm" = ["mpv.desktop"];
        "video/x-msvideo" = ["mpv.desktop"];
        "video/quicktime" = ["mpv.desktop"];

        "audio/mpeg" = ["mpv.desktop"];
        "audio/flac" = ["mpv.desktop"];
        "audio/ogg" = ["mpv.desktop"];
        "audio/wav" = ["mpv.desktop"];
        "audio/x-wav" = ["mpv.desktop"];
        "audio/aac" = ["mpv.desktop"];

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

        "application/zip" = ["org.kde.ark.desktop"];
        "application/x-tar" = ["org.kde.ark.desktop"];
        "application/x-bzip" = ["org.kde.ark.desktop"];
        "application/x-xz" = ["org.kde.ark.desktop"];
        "application/gzip" = ["org.kde.ark.desktop"];
        "application/x-7z-compressed" = ["org.kde.ark.desktop"];
        "application/x-compressed-tar" = ["org.kde.ark.desktop"];

        "application/epub+zip" = ["org.pwmt.zathura-pdf-mupdf.desktop"];
        "application/x-bittorrent" = ["org.qbittorrent.qBittorrent.desktop"];
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
    ".config/hypr/hyprland.conf".source = link "${dots}/.config/hypr/hyprland.conf";
    ".config/hypr/hypridle.conf".source = link "${dots}/.config/hypr/hypridle.conf";
    ".config/hypr/hyprlock.conf".source = link "${dots}/.config/hypr/hyprlock.conf";
    ".config/hypr/hyprpaper.conf".source = link "${dots}/.config/hypr/hyprpaper.conf";
    ".config/hypr/keybinds.conf".source = link "${dots}/.config/hypr/keybinds.conf";
    ".config/hypr/monitors.conf".source = link "${dots}/.config/hypr/monitors.conf";
    ".config/pypr/config.toml".source = link "${dots}/.config/pypr/config.toml";
    ".config/hypr/workspaces.conf".source = link "${dots}/.config/hypr/workspaces.conf";
    ".config/foot/foot.ini".source = link "${dots}/.config/foot/foot.ini";
    ".config/foot/color-dark.ini".source = link "${dots}/.config/foot/color-dark.ini";
    ".config/foot/colors-light.ini".source = link "${dots}/.config/foot/colors-light.ini";
    ".config/tofi/config".source = link "${dots}/.config/tofi/config";
    # ".config/mako/config".source = link "${dots}/.config/mako/config";
    ".config/ironbar/config.toml".source = link "${dots}/.config/ironbar/config.toml";

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

    ".config/blueman" = {
      source = link "${dots}/.config/blueman";
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

    ".config/BraveSoftware/Brave-Origin-Beta/NativeMessagingHosts/com.github.browserpass.native.json".source =
      "${pkgs.browserpass}/lib/browserpass/hosts/chromium/com.github.browserpass.native.json";

    ".config/BraveSoftware/Brave-Origin-Nightly/NativeMessagingHosts/com.github.browserpass.native.json".source =
      "${pkgs.browserpass}/lib/browserpass/hosts/chromium/com.github.browserpass.native.json";

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
  };
}
