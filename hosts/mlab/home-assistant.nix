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
  xgimiHost = "192.168.1.202";
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
                columns = 2;
                square = false;
                cards = [
                  (tvBoxHoldButton "Long OK" "mdi:gesture-tap-hold" "DPAD_CENTER")
                  (tvBoxHoldButton "Long Back" "mdi:keyboard-return" "BACK")
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
        xgimi_settings = "${pkgs.lib.getExe xgimiAdb} shell am start -n com.android.newsettings/com.xgimi.newsettings.mock.MockActivity";
        xgimi_input = "${pkgs.lib.getExe xgimiAdb} shell am start -n com.mstar.tvsetting/.switchinputsource.PictrueChangeActivity";
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
                        timeout = "00:00:05";
                        continue_on_timeout = true;
                      }
                    ];
                    until = [
                      {
                        condition = "template";
                        value_template = "{{ not is_state('${tvBoxMediaPlayer}', 'unavailable') or repeat.index >= 8 }}";
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
  ];
}
