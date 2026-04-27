{
  config,
  _pkgs,
  services,
  ...
}: let
  companionPort = 8282;
in {
  services.invidious = {
    enable = true;
    domain = services.youtube.href;
    port = services.youtube.port;
    nginx.enable = false;
    database.createLocally = true;

    extraSettingsFile = config.sops.templates."invidious-extra.json".path;

    settings = {
      login_only = true;
      login_enabled = true;
      registration_enabled = false;
      unauthenticated_search_query_limit = 0;
      captcha_enabled = false;
      pwned_check = false;
      invidious_companion = [
        {
          private_url = "http://127.0.0.1:${toString companionPort}/companion";
        }
      ];
      default_user_preferences = {
        dark_mode = "dark";
        autoplay = false;
      };
    };
  };

  virtualisation.oci-containers.containers.invidious-companion = {
    image = "quay.io/invidious/invidious-companion:latest";
    environmentFiles = [
      config.sops.templates."invidious-companion.env".path
    ];
    extraOptions = [
      "--network=host"
      "--read-only"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
    ];
    volumes = [
      "invidious-companion-cache:/var/tmp/youtubei.js:rw"
    ];
  };
}
