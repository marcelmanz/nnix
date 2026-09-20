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
    domain = builtins.replaceStrings ["https://" "http://"] ["" ""] services.youtube.href;
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
      channel_threads = 1; # was 0 (blocked by YouTube), re-enabled: needed to actually refresh subscriptions
      feed_threads = 1; # use RSS feeds instead (works reliably)
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
    pull = "newer";
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

  # PO token logic changes often upstream; the default pull policy ("missing")
  # left this image untouched for 5 months. "newer" + a weekly restart keeps it
  # current without pinning a digest that would have to be bumped by hand.
  systemd.services.invidious-companion-update = {
    description = "Restart invidious-companion so it pulls a newer image";
    startAt = "weekly";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/systemctl restart podman-invidious-companion.service";
    };
  };
}
