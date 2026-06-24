# {
#   config,
#   pkgs,
#   ...
# }: let
#   domain = "matrix.marcel.cool";
#   callDomain = "call.matrix.marcel.cool";
#   serverName = "marcel.cool";
#
#   elementCallPackage = pkgs.element-web;
#
#   elementCallConfig = pkgs.writeText "element-call-config.json" ''
#     {
#       "default_server_config": {
#         "m.homeserver": {
#           "base_url": "https://${domain}/",
#           "server_name": "${serverName}"
#         }
#       },
#       "features": {
#         "feature_use_device_session_member_events": true
#       },
#       "livekit": {
#         "livekit_service_url": "https://${domain}/livekit/jwt"
#       },
#       "matrix_rtc_session": {
#         "wait_for_key_rotation_ms": 5000,
#         "membership_event_expiry_ms": 7200000,
#         "delayed_leave_event_delay_ms": 90000,
#         "delayed_leave_event_restart_ms": 4000,
#         "delayed_leave_event_restart_local_timeout_ms": 10000,
#         "network_error_retry_ms": 100
#       },
#       "matrix_rtc_transport": {
#         "type": "livekit",
#         "livekit_service_url": "https://${domain}/livekit/jwt"
#       }
#     }
#   '';
#
# in {
#   services.nginx.virtualHosts.${domain} = {
#     locations."/" = {
#       root = elementCallPackage;
#       index = "index.html";
#       extraConfig = "try_files $uri $uri/ /index.html =404;";
#     };
#   };
#
#   services.nginx.virtualHosts.${callDomain} = {
#     forceSSL = true;
#     useACMEHost = "matrix.marcel.cool";
#     locations."/" = {
#       root = pkgs.element-call;
#       extraConfig = "try_files $uri $uri/ /index.html =404;";
#     };
#     locations."/config.json" = {
#       extraConfig = "add_header Content-Type application/json; add_header Access-Control-Allow-Origin *; return 200 '${builtins.readFile elementCallConfig}';";
#     };
#   };
#
#   environment.etc."element-call/config.json".source = elementCallConfig;
# }
