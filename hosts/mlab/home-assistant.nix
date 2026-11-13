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
                type = "custom:universal-remote-card";
                platform = "Android TV";
                remote_id = tvBoxRemote;
                media_player_id = tvBoxMediaPlayer;
                rows = [
                  ["back" "home" "power"]
                  ["dpad"]
                  ["rewind" "play" "pause" "fast_forward"]
                  ["volume_down" "volume_mute" "volume_up"]
                ];
                custom_actions = [
                  {
                    type = "button";
                    name = "power";
                    icon = "mdi:power";
                    tap_action = {
                      action = "perform-action";
                      perform_action = "switch.toggle";
                      target.entity_id = "switch.xiaomi_tv_box";
                    };
                  }
                  {
                    type = "button";
                    name = "play";
                    icon = "mdi:play";
                    tap_action = {
                      action = "key";
                      key = "MEDIA_PLAY";
                    };
                  }
                  {
                    type = "button";
                    name = "pause";
                    icon = "mdi:pause";
                    tap_action = {
                      action = "key";
                      key = "MEDIA_PAUSE";
                    };
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
                columns = 4;
                square = false;
                cards = [
                  {
                    type = "button";
                    entity = "switch.xgimi_h3";
                    name = "Power";
                    icon = "mdi:power";
                    tap_action.action = "toggle";
                  }
                  (xgimiButton "Menu" "mdi:menu" "139")
                  (xgimiButton "Mute" "mdi:volume-mute" "113")
                  (xgimiButton "Focus" "mdi:image-filter-center-focus" "2099")
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
    customLovelaceModules = [
      pkgs.home-assistant-custom-lovelace-modules.universal-remote-card
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
        xgimi_wake = pkgs.lib.getExe xgimiWake;
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
