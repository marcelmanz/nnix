{
  config,
  pkgs,
  services,
  ...
}: let
  tvBoxHost = "192.168.1.199";
  tvBoxMac = "70:68:71:f9:e9:e6";
  tvBoxRemote = "remote.living_room_xiao_mitv";
  tvBoxMediaPlayer = "media_player.living_room_xiao_mitv";
  xgimiHost = "192.168.1.206";
  xgimiKey = pkgs.writeShellApplication {
    name = "xgimi-key";
    runtimeInputs = [pkgs.netcat-openbsd];
    text = ''
      case "''${1:-}" in
        "" | *[!0-9]*) echo "usage: xgimi-key <keycode>" >&2; exit 1 ;;
      esac
      printf 'KEYPRESSES:%s' "$1" | nc -u -w 1 ${xgimiHost} 16735
    '';
  };
  xgimiWake = pkgs.writeShellApplication {
    name = "xgimi-wake";
    runtimeInputs = [pkgs.bluez pkgs.coreutils];
    text = ''
      token=$(cat ${config.sops.secrets.xgimi_ble_token.path})
      for i in 1 2 3 4 5; do
        counter=$(printf '%02X' $(( ($(date +%s) + i) % 256 )))
        btmgmt --index 0 add-adv -d "02010613FF4600''${counter}''${token}" -t 3 1 >/dev/null
        sleep 3
      done
      btmgmt --index 0 rm-adv 1 >/dev/null
    '';
  };
  xgimiFocus = pkgs.writeShellApplication {
    name = "xgimi-focus";
    runtimeInputs = [pkgs.netcat-openbsd pkgs.coreutils];
    text = ''
      case "''${1:-}" in
        253 | 254) ;;
        *) echo "usage: xgimi-focus <253|254>" >&2; exit 1 ;;
      esac
      printf 'KEYSSTATUS:%s+1' "$1" | nc -u -w 1 ${xgimiHost} 16735
      sleep 0.3
      printf 'KEYSSTATUS:%s+0' "$1" | nc -u -w 1 ${xgimiHost} 16735
    '';
  };
  xgimiAdb = pkgs.writeShellApplication {
    name = "xgimi-adb";
    runtimeInputs = [pkgs.android-tools];
    text = ''
      export HOME=/var/lib/hass
      adb connect ${xgimiHost}:5555 >/dev/null 2>&1 || true
      exec adb -s ${xgimiHost}:5555 "$@"
    '';
  };
  tvBoxAdb = pkgs.writeShellApplication {
    name = "tv-box-adb";
    runtimeInputs = [pkgs.android-tools];
    text = ''
      export HOME=/var/lib/hass
      adb connect ${tvBoxHost}:5555 >/dev/null 2>&1 || true
      exec adb -s ${tvBoxHost}:5555 "$@"
    '';
  };
  xgimiButton = name: icon: key: {
    type = "button";
    inherit name icon;
    show_state = false;
    tap_action = {
      action = "perform-action";
      perform_action = "shell_command.xgimi_key";
      data.key = key;
    };
  };
  xgimiActionButton = name: icon: action: {
    type = "button";
    inherit name icon;
    show_state = false;
    tap_action = {
      action = "perform-action";
      perform_action = "shell_command.${action}";
    };
  };
  xgimiFocusButton = name: icon: code: {
    type = "button";
    inherit name icon;
    show_state = false;
    tap_action = {
      action = "perform-action";
      perform_action = "shell_command.xgimi_focus";
      data.code = code;
    };
  };
  tvBoxButton = name: icon: command: {
    type = "button";
    inherit name icon;
    show_state = false;
    tap_action = {
      action = "perform-action";
      perform_action = "remote.send_command";
      target.entity_id = tvBoxRemote;
      data.command = command;
    };
  };
  tvBoxHoldButton = name: icon: command: {
    type = "button";
    inherit name icon;
    show_state = false;
    tap_action = {
      action = "perform-action";
      perform_action = "remote.send_command";
      target.entity_id = tvBoxRemote;
      data = {
        command = command;
        hold_secs = 1;
      };
    };
  };
  tvKeyboardRemoteJs = pkgs.writeText "tv-keys.js" ''
    const keyCommands = {
      ArrowUp: "DPAD_UP",
      ArrowDown: "DPAD_DOWN",
      ArrowLeft: "DPAD_LEFT",
      ArrowRight: "DPAD_RIGHT",
      " ": "DPAD_CENTER",
      Enter: "DPAD_CENTER",
      Backspace: "BACK",
      Escape: "BACK",
      h: "HOME",
      m: "MENU",
      a: "APP_SWITCH",
      p: "MEDIA_PLAY_PAUSE",
      MediaPlayPause: "MEDIA_PLAY_PAUSE",
      "0": "VOLUME_MUTE",
      "-": "VOLUME_DOWN",
      "+": "VOLUME_UP",
      "=": "VOLUME_UP",
      AudioVolumeDown: "VOLUME_DOWN",
      AudioVolumeUp: "VOLUME_UP",
      AudioVolumeMute: "VOLUME_MUTE",
    };

    const codeCommands = {
      Minus: "VOLUME_DOWN",
      NumpadSubtract: "VOLUME_DOWN",
      Equal: "VOLUME_UP",
      NumpadAdd: "VOLUME_UP",
    };

    const isTyping = (event) =>
      event.composedPath().some(
        (el) => el instanceof HTMLElement && (el.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName)),
      );

    const deepFind = (root, selector) => {
      const hit = root.querySelector(selector);
      if (hit) return hit;
      for (const el of root.querySelectorAll("*")) {
        const found = el.shadowRoot && deepFind(el.shadowRoot, selector);
        if (found) return found;
      }
      return null;
    };

    const tvTextRowTag = "hui-input-text-entity-row";

    const isInTvTextField = (event) =>
      event.composedPath().some((el) => el.tagName === tvTextRowTag.toUpperCase());

    const focusTvTextField = () => {
      const row = deepFind(document, tvTextRowTag);
      const input = row?.shadowRoot && deepFind(row.shadowRoot, "input");
      input?.focus();
      return Boolean(input);
    };

    const legendRows = [
      ["Arrow keys", "Navigate"],
      ["Space / Enter", "OK"],
      ["Backspace / Esc", "Back"],
      ["H", "Home"],
      ["M", "Menu"],
      ["A", "Apps"],
      ["P", "Play / pause"],
      ["+ / -", "Volume up / down"],
      ["0", "Mute"],
      ["K", "Type on TV (Enter sends, Esc leaves)"],
      ["C", "Mouse mode (Esc leaves)"],
      ["?", "Show / hide this legend"],
    ];

    const isOnTvDashboard = () => location.pathname.startsWith("/dashboard-tv/");

    const style = document.createElement("style");
    style.textContent = `
      #tv-keys-toolbar {
        position: fixed; top: 10px; left: 50%; transform: translateX(-50%); z-index: 10;
        display: flex; gap: 8px;
      }
      #tv-keys-toolbar[hidden] { display: none; }
      @media not ((hover: hover) and (pointer: fine)) { #tv-keys-toolbar { display: none; } }
      .tv-keys-button {
        padding: 6px 14px; border-radius: 18px; border: 1px solid var(--divider-color);
        background: var(--card-background-color); color: var(--primary-text-color);
        font: inherit; font-size: 14px; cursor: pointer;
      }
      #tv-keys-legend .tv-keys-button { margin-top: 16px; }
      #tv-mouse-pairing { margin: 8px 0 0; max-width: 360px; font-size: 13px; color: var(--secondary-text-color); }
      #tv-mouse-indicator {
        position: fixed; bottom: 16px; left: 50%; transform: translateX(-50%); z-index: 11;
        padding: 8px 16px; border-radius: 18px; background: rgba(0, 0, 0, 0.75); color: #fff;
        font-family: var(--ha-font-family-body, sans-serif); font-size: 14px; pointer-events: none;
      }
      #tv-mouse-indicator[hidden] { display: none; }
      #tv-keys-legend {
        position: fixed; inset: 0; z-index: 11; display: flex; align-items: center; justify-content: center;
        background: rgba(0, 0, 0, 0.5);
      }
      #tv-keys-legend[hidden] { display: none; }
      #tv-keys-legend > div {
        max-width: calc(100vw - 32px); padding: 20px 24px; border-radius: 12px;
        background: var(--card-background-color); color: var(--primary-text-color);
        font-family: var(--ha-font-family-body, sans-serif); box-shadow: 0 8px 32px rgba(0, 0, 0, 0.4);
      }
      #tv-keys-legend h2 { margin: 0 0 12px; font-size: 18px; font-weight: 500; }
      #tv-keys-legend table { border-collapse: collapse; }
      #tv-keys-legend td { padding: 4px 16px 4px 0; vertical-align: top; }
      #tv-keys-legend kbd {
        padding: 1px 6px; border: 1px solid var(--divider-color); border-radius: 4px;
        font-family: var(--ha-font-family-code, monospace); font-size: 13px; white-space: nowrap;
      }
    `;
    document.head.append(style);

    const legend = document.createElement("div");
    legend.id = "tv-keys-legend";
    legend.hidden = true;
    const legendPanel = document.createElement("div");
    const legendTitle = document.createElement("h2");
    legendTitle.textContent = "Keyboard remote";
    const legendTable = document.createElement("table");
    for (const [keys, action] of legendRows) {
      const row = legendTable.insertRow();
      const kbd = document.createElement("kbd");
      kbd.textContent = keys;
      row.insertCell().append(kbd);
      row.insertCell().textContent = action;
    }
    const pairButton = document.createElement("button");
    pairButton.className = "tv-keys-button";
    pairButton.textContent = "Pair mouse with TV";
    const pairingText = document.createElement("p");
    pairingText.id = "tv-mouse-pairing";
    legendPanel.append(legendTitle, legendTable, pairButton, pairingText);
    legend.append(legendPanel);
    legend.addEventListener("click", (event) => {
      if (event.target === legend) legend.hidden = true;
    });

    const toolbar = document.createElement("div");
    toolbar.id = "tv-keys-toolbar";
    const legendButton = document.createElement("button");
    legendButton.className = "tv-keys-button";
    legendButton.textContent = "Keys";
    legendButton.addEventListener("click", () => {
      legend.hidden = !legend.hidden;
      legendButton.blur();
    });
    const mouseButton = document.createElement("button");
    mouseButton.className = "tv-keys-button";
    mouseButton.textContent = "Mouse";
    toolbar.append(legendButton, mouseButton);

    const mouseIndicator = document.createElement("div");
    mouseIndicator.id = "tv-mouse-indicator";
    mouseIndicator.hidden = true;

    document.body.append(toolbar, legend, mouseIndicator);

    let mouseSocket = null;
    let mouseStatus = { connected: false, pairing: 0 };
    let mouseButtons = 0;
    let mouseDx = 0;
    let mouseDy = 0;
    let wheelPixels = 0;
    let mouseDirty = false;
    let lastPointerLockExit = 0;
    const wheelPixelsPerStep = 100;

    const isMouseMode = () => document.pointerLockElement === document.body;

    const renderMouseStatus = () => {
      mouseIndicator.hidden = !isMouseMode();
      mouseIndicator.textContent = mouseStatus.connected
        ? "Mouse mode: TV connected. Esc to leave"
        : mouseStatus.paired
          ? "Mouse mode: connecting to TV... Esc to leave"
          : "Mouse mode: not paired yet, use Pair mouse with TV in the Keys legend. Esc to leave";
      pairingText.textContent = mouseStatus.pairing
        ? "mlab is discoverable for 2 minutes. On the TV open Settings > Remotes & accessories > Add accessory and pick mlab."
        : mouseStatus.connected
          ? "TV mouse connected."
          : "";
    };

    const openMouseSocket = () => {
      if (mouseSocket && mouseSocket.readyState <= WebSocket.OPEN) return mouseSocket;
      mouseSocket = new WebSocket("wss://" + location.host + "/tv-mouse/");
      mouseSocket.addEventListener("message", (event) => {
        mouseStatus = JSON.parse(event.data);
        renderMouseStatus();
      });
      mouseSocket.addEventListener("close", () => {
        mouseStatus = { connected: false, pairing: 0 };
        renderMouseStatus();
      });
      return mouseSocket;
    };

    const enterMouseMode = () => {
      openMouseSocket();
      legend.hidden = true;
      document.body.requestPointerLock();
    };

    mouseButton.addEventListener("click", () => {
      mouseButton.blur();
      enterMouseMode();
    });

    pairButton.addEventListener("click", () => {
      const socket = openMouseSocket();
      const pair = () => socket.send(JSON.stringify({ pair: true }));
      if (socket.readyState === WebSocket.OPEN) pair();
      else socket.addEventListener("open", pair, { once: true });
      pairingText.textContent = "Opening pairing...";
    });

    document.addEventListener("pointerlockchange", () => {
      if (!isMouseMode()) {
        lastPointerLockExit = performance.now();
        if (mouseButtons) {
          mouseButtons = 0;
          mouseDirty = true;
        }
      }
      renderMouseStatus();
    });

    document.addEventListener("mousemove", (event) => {
      if (!isMouseMode()) return;
      mouseDx += event.movementX;
      mouseDy += event.movementY;
      mouseDirty = true;
    });

    const updateMouseButtons = (event) => {
      if (!isMouseMode()) return;
      event.preventDefault();
      event.stopPropagation();
      mouseButtons = event.buttons & 0x07;
      mouseDirty = true;
    };
    document.addEventListener("mousedown", updateMouseButtons, true);
    document.addEventListener("mouseup", updateMouseButtons, true);
    document.addEventListener(
      "contextmenu",
      (event) => {
        if (isMouseMode()) event.preventDefault();
      },
      true,
    );
    document.addEventListener(
      "wheel",
      (event) => {
        if (!isMouseMode()) return;
        event.preventDefault();
        wheelPixels += event.deltaMode === WheelEvent.DOM_DELTA_LINE ? event.deltaY * 33 : event.deltaY;
        mouseDirty = true;
      },
      { capture: true, passive: false },
    );

    const flushMouse = () => {
      requestAnimationFrame(flushMouse);
      if (!mouseDirty || mouseSocket?.readyState !== WebSocket.OPEN) return;
      const dx = Math.trunc(mouseDx);
      const dy = Math.trunc(mouseDy);
      const wheelSteps = Math.trunc(wheelPixels / wheelPixelsPerStep);
      mouseDx -= dx;
      mouseDy -= dy;
      wheelPixels -= wheelSteps * wheelPixelsPerStep;
      mouseDirty = false;
      mouseSocket.send(JSON.stringify({ report: [mouseButtons, dx, dy, -wheelSteps] }));
    };
    requestAnimationFrame(flushMouse);

    const updateLegendVisibility = () => {
      toolbar.hidden = !isOnTvDashboard();
      if (!isOnTvDashboard()) {
        legend.hidden = true;
        if (isMouseMode()) document.exitPointerLock();
      }
    };
    updateLegendVisibility();
    window.addEventListener("location-changed", updateLegendVisibility);
    window.addEventListener("popstate", updateLegendVisibility);

    window.addEventListener(
      "keydown",
      (event) => {
        if (!isOnTvDashboard()) return;
        if (event.key === "Escape" && (isMouseMode() || performance.now() - lastPointerLockExit < 500)) {
          event.preventDefault();
          event.stopPropagation();
          return;
        }
        if (!legend.hidden && event.key === "Escape") {
          event.preventDefault();
          event.stopPropagation();
          legend.hidden = true;
          return;
        }
        if (event.key === "Escape" && isInTvTextField(event)) {
          event.preventDefault();
          event.stopPropagation();
          event.composedPath()[0].blur();
          return;
        }
        if (event.ctrlKey || event.altKey || event.metaKey || isTyping(event)) return;
        if (event.key === "?") {
          event.preventDefault();
          event.stopPropagation();
          legend.hidden = !legend.hidden;
          return;
        }
        if (event.key === "c") {
          event.preventDefault();
          event.stopPropagation();
          enterMouseMode();
          return;
        }
        if (event.key === "k" && focusTvTextField()) {
          event.preventDefault();
          event.stopPropagation();
          return;
        }
        const command = keyCommands[event.key] ?? codeCommands[event.code];
        const hass = document.querySelector("home-assistant")?.hass;
        if (!command || !hass) return;
        event.preventDefault();
        event.stopPropagation();
        hass.callService("remote", "send_command", { entity_id: "${tvBoxRemote}", command });
      },
      true,
    );
  '';
  tvDashboard = (pkgs.formats.yaml {}).generate "dashboard-tv.yaml" {
    title = "TV";
    views = [
      {
        title = "TV";
        path = "tv";
        type = "panel";
        cards = [
          {
            type = "vertical-stack";
            cards = [
              {
                type = "heading";
                heading = "Xiaomi TV Box";
              }
              {
                type = "grid";
                columns = 4;
                square = false;
                cards = [
                  {
                    type = "button";
                    entity = "switch.xiaomi_tv_box";
                    name = "Power";
                    icon = "mdi:power";
                    tap_action.action = "toggle";
                  }
                  (tvBoxButton "Menu" "mdi:menu" "MENU")
                  (tvBoxButton "Apps" "mdi:view-grid" "APP_SWITCH")
                  (tvBoxButton "Mute" "mdi:volume-mute" "VOLUME_MUTE")
                ];
              }
              {
                type = "grid";
                columns = 3;
                square = false;
                cards = [
                  (tvBoxButton "Back" "mdi:arrow-left" "BACK")
                  (tvBoxButton "Up" "mdi:chevron-up" "DPAD_UP")
                  (tvBoxButton "Home" "mdi:home" "HOME")
                  (tvBoxButton "Left" "mdi:chevron-left" "DPAD_LEFT")
                  (tvBoxButton "OK" "mdi:circle-medium" "DPAD_CENTER")
                  (tvBoxButton "Right" "mdi:chevron-right" "DPAD_RIGHT")
                  (tvBoxButton "Vol -" "mdi:volume-minus" "VOLUME_DOWN")
                  (tvBoxButton "Down" "mdi:chevron-down" "DPAD_DOWN")
                  (tvBoxButton "Vol +" "mdi:volume-plus" "VOLUME_UP")
                ];
              }
              {
                type = "grid";
                columns = 3;
                square = false;
                cards = [
                  (tvBoxHoldButton "Long OK" "mdi:gesture-tap-hold" "DPAD_CENTER")
                  (tvBoxHoldButton "Long Back" "mdi:keyboard-return" "BACK")
                  (xgimiActionButton "Restart BT" "mdi:bluetooth-off" "tv_box_bluetooth_restart")
                ];
              }
              {
                type = "entities";
                entities = [
                  {
                    entity = "input_text.tv_search";
                    name = "Type on TV";
                    icon = "mdi:keyboard";
                  }
                ];
              }
              {
                type = "media-control";
                entity = tvBoxMediaPlayer;
              }
              {
                type = "heading";
                heading = "XGIMI H3";
              }
              {
                type = "grid";
                columns = 3;
                square = false;
                cards = [
                  {
                    type = "button";
                    entity = "switch.xgimi_h3";
                    name = "Power";
                    icon = "mdi:power";
                    tap_action.action = "toggle";
                  }
                  (xgimiActionButton "Input" "mdi:video-input-hdmi" "xgimi_input")
                  (xgimiActionButton "Settings" "mdi:cog" "xgimi_settings")
                  (xgimiButton "Menu" "mdi:menu" "139")
                  (xgimiFocusButton "Focus +" "mdi:plus" "253")
                  (xgimiFocusButton "Focus -" "mdi:minus" "254")
                ];
              }
              {
                type = "grid";
                columns = 3;
                square = false;
                cards = [
                  (xgimiButton "Back" "mdi:arrow-left" "48")
                  (xgimiButton "Up" "mdi:chevron-up" "36")
                  (xgimiButton "Home" "mdi:home" "35")
                  (xgimiButton "Left" "mdi:chevron-left" "50")
                  (xgimiButton "OK" "mdi:circle-medium" "49")
                  (xgimiButton "Right" "mdi:chevron-right" "37")
                  (xgimiButton "Vol -" "mdi:volume-minus" "114")
                  (xgimiButton "Down" "mdi:chevron-down" "38")
                  (xgimiButton "Vol +" "mdi:volume-plus" "115")
                ];
              }
            ];
          }
        ];
      }
    ];
  };
  homeDashboard = (pkgs.formats.yaml {}).generate "dashboard-home.yaml" {
    title = "Home";
    views = [
      {
        title = "Home";
        path = "home";
        cards = [
          {
            type = "weather-forecast";
            entity = "weather.forecast_home";
            forecast_type = "daily";
          }
          {
            type = "vertical-stack";
            cards = [
              {
                type = "heading";
                heading = "TV";
              }
              {
                type = "grid";
                columns = 3;
                square = false;
                cards = [
                  {
                    type = "button";
                    entity = "switch.xiaomi_tv_box";
                    name = "TV Box";
                    tap_action.action = "toggle";
                  }
                  {
                    type = "button";
                    entity = "switch.xgimi_h3";
                    name = "Projector";
                    tap_action.action = "toggle";
                  }
                  {
                    type = "button";
                    name = "Remote";
                    icon = "mdi:remote-tv";
                    show_state = false;
                    tap_action = {
                      action = "navigate";
                      navigation_path = "/dashboard-tv/tv";
                    };
                  }
                ];
              }
              {
                type = "media-control";
                entity = tvBoxMediaPlayer;
              }
            ];
          }
        ];
      }
    ];
  };
in {
  services.home-assistant = {
    enable = true;
    extraComponents = [
      "default_config"
      "met"
      "esphome"
      "command_line"
      "mobile_app"
      "radio_browser"
      "google_translate"
      "isal"
      "androidtv_remote"
      "wake_on_lan"
      "template"
    ];
    config = {
      default_config = {};
      homeassistant = {
        name = "Home";
        time_zone = config.time.timeZone;
        unit_system = "metric";
        external_url = services.homeassistant.href;
      };
      "automation ui" = "!include automations.yaml";
      "automation manual" = [
        {
          alias = "Turn on TV box when projector turns on";
          id = "projector_on_box_on";
          mode = "single";
          trigger = [
            {
              platform = "state";
              entity_id = "binary_sensor.xgimi_h3";
              from = "off";
              to = "on";
            }
          ];
          action = [
            {
              action = "switch.turn_on";
              target.entity_id = "switch.xiaomi_tv_box";
            }
          ];
        }
        {
          alias = "Send typed text to TV box";
          id = "tv_search_send_text";
          mode = "queued";
          trigger = [
            {
              platform = "state";
              entity_id = "input_text.tv_search";
            }
          ];
          condition = [
            {
              condition = "template";
              value_template = "{{ trigger.to_state.state not in ['', 'unknown', 'unavailable'] }}";
            }
          ];
          action = [
            {
              action = "remote.send_command";
              target.entity_id = tvBoxRemote;
              data.command = "text:{{ trigger.to_state.state }}";
            }
            {
              action = "input_text.set_value";
              target.entity_id = "input_text.tv_search";
              data.value = "";
            }
          ];
        }
      ];
      frontend.extra_module_url = [
        "/local/tv-keys.js?v=${builtins.substring 0 8 (builtins.hashString "sha256" (builtins.unsafeDiscardStringContext "${tvKeyboardRemoteJs}"))}"
      ];
      input_text.tv_search = {
        name = "Type on TV";
        max = 200;
        initial = "";
      };
      lovelace.dashboards.dashboard-home = {
        mode = "yaml";
        filename = "${homeDashboard}";
        title = "Home";
        icon = "mdi:home";
        show_in_sidebar = true;
      };
      lovelace.dashboards.dashboard-tv = {
        mode = "yaml";
        filename = "${tvDashboard}";
        title = "TV";
        icon = "mdi:remote-tv";
        show_in_sidebar = true;
      };
      command_line = [
        {
          binary_sensor = {
            name = "Xiaomi TV Box";
            unique_id = "xiaomi_tv_box_power";
            command = "${pkgs.netcat-openbsd}/bin/nc -z -w 3 ${tvBoxHost} 5555 && echo on || echo off";
            payload_on = "on";
            payload_off = "off";
            device_class = "power";
            scan_interval = 15;
          };
        }
        {
          binary_sensor = {
            name = "XGIMI H3";
            unique_id = "xgimi_h3_power";
            command = "${pkgs.netcat-openbsd}/bin/nc -z -w 3 ${xgimiHost} 554 && echo on || echo off";
            payload_on = "on";
            payload_off = "off";
            device_class = "power";
            scan_interval = 15;
          };
        }
      ];
      shell_command = {
        xgimi_key = "${pkgs.lib.getExe xgimiKey} {{ key }}";
        xgimi_focus = "${pkgs.lib.getExe xgimiFocus} {{ code }}";
        xgimi_wake = pkgs.lib.getExe xgimiWake;
        xgimi_settings = "${pkgs.lib.getExe xgimiAdb} shell am startservice -n com.android.newsettings/com.xgimi.newsettings.SettingService -a com.xgimi.settings.SETTINGS";
        xgimi_input = "${pkgs.lib.getExe xgimiAdb} shell am start -n com.mstar.tvsetting/.switchinputsource.PictrueChangeActivity";
        # clears a stuck bond that makes Pair accessory hang with createBond BUSY
        tv_box_bluetooth_restart = "${pkgs.lib.getExe tvBoxAdb} shell 'cmd bluetooth_manager disable && sleep 3 && cmd bluetooth_manager enable'";
      };
      wake_on_lan = {};
      template = [
        {
          switch = [
            {
              name = "Xiaomi TV Box";
              unique_id = "xiaomi_tv_box_switch";
              icon = "mdi:television-box";
              state = "{{ is_state('binary_sensor.xiaomi_tv_box', 'on') }}";
              turn_on = [
                {
                  repeat = {
                    count = 3;
                    sequence = [
                      {
                        action = "wake_on_lan.send_magic_packet";
                        data = {
                          mac = tvBoxMac;
                          broadcast_address = "192.168.1.255";
                        };
                      }
                      {delay = "00:00:00.2";}
                    ];
                  };
                }
                {
                  repeat = {
                    sequence = [
                      {
                        action = "wake_on_lan.send_magic_packet";
                        data = {
                          mac = tvBoxMac;
                          broadcast_address = "192.168.1.255";
                        };
                      }
                      {
                        wait_template = "{{ not is_state('${tvBoxMediaPlayer}', 'unavailable') }}";
                        timeout = "00:00:02";
                        continue_on_timeout = true;
                      }
                    ];
                    until = [
                      {
                        condition = "template";
                        value_template = "{{ not is_state('${tvBoxMediaPlayer}', 'unavailable') or repeat.index >= 20 }}";
                      }
                    ];
                  };
                }
                {
                  condition = "template";
                  value_template = "{{ not is_state('${tvBoxMediaPlayer}', 'unavailable') }}";
                }
                {
                  action = "remote.send_command";
                  target.entity_id = tvBoxRemote;
                  data.command = "KEYCODE_WAKEUP";
                }
                {
                  action = "homeassistant.update_entity";
                  target.entity_id = "binary_sensor.xiaomi_tv_box";
                }
              ];
              turn_off = [
                {
                  action = "media_player.turn_off";
                  target.entity_id = tvBoxMediaPlayer;
                }
              ];
            }
            {
              name = "XGIMI H3";
              unique_id = "xgimi_h3_switch";
              icon = "mdi:projector";
              state = "{{ is_state('binary_sensor.xgimi_h3', 'on') }}";
              turn_on = [
                {action = "shell_command.xgimi_wake";}
                {
                  action = "homeassistant.update_entity";
                  target.entity_id = "binary_sensor.xgimi_h3";
                }
              ];
              turn_off = [
                {
                  action = "shell_command.xgimi_key";
                  data.key = "30";
                }
                {
                  action = "homeassistant.update_entity";
                  target.entity_id = "binary_sensor.xgimi_h3";
                }
              ];
            }
          ];
        }
      ];
    };
  };

  sops.secrets.xgimi_ble_token.owner = "hass";

  systemd.tmpfiles.rules = [
    "f ${config.services.home-assistant.configDir}/automations.yaml 0644 hass hass"
    "d ${config.services.home-assistant.configDir}/www 0755 hass hass"
    "L+ ${config.services.home-assistant.configDir}/www/tv-keys.js - - - - ${tvKeyboardRemoteJs}"
  ];
}
