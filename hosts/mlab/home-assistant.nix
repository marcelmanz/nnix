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
  xgimiComponent = pkgs.buildHomeAssistantComponent {
    owner = "manymuch";
    domain = "xgimi";
    version = "1.1.4";
    src = pkgs.fetchFromGitHub {
      owner = "manymuch";
      repo = "Xgimi-4-Home-Assistant";
      rev = "edbaae867e02adcb7cbf7b6e2cac805c4dcd1ec2";
      hash = "sha256-Rb55QTJHXmoFQs23jGWWeATUQCyZlU7Zr/VWFkCz3Cg=";
    };
    dependencies = with pkgs.home-assistant.python3Packages; [
      asyncudp
      dbus-fast
    ];
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
    customComponents = [
      xgimiComponent
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
      ];
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
          ];
        }
      ];
    };
  };

  systemd.tmpfiles.rules = [
    "f ${config.services.home-assistant.configDir}/automations.yaml 0644 hass hass"
  ];
}
