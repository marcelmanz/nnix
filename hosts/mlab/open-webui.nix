{
  config,
  inputs,
  services,
  ...
}: let
  synthetic = (builtins.fromJSON (builtins.readFile "${inputs.dots}/.pi/agent/models.json")).providers.synthetic;
in {
  sops.templates."open-webui.env".content = ''
    OPENAI_API_KEY=${config.sops.placeholder.synthetic_api_key}
  '';

  services.open-webui = {
    enable = true;
    host = "0.0.0.0";
    port = services.openwebui.port;
    environmentFile = config.sops.templates."open-webui.env".path;
    environment = {
      SCARF_NO_ANALYTICS = "True";
      DO_NOT_TRACK = "True";
      ANONYMIZED_TELEMETRY = "False";

      # the UI settings live in webui.db and shadow these env vars unless
      # persistence is off, so the whole config comes from here instead.
      ENABLE_PERSISTENT_CONFIG = "False";

      ENABLE_OPENAI_API = "True";
      OPENAI_API_BASE_URL = synthetic.baseUrl;
      OPENAI_API_CONFIGS = builtins.toJSON {
        "0" = {
          enable = true;
          model_ids = map (model: model.id) synthetic.models;
        };
      };

      ENABLE_WEB_SEARCH = "True";
      WEB_SEARCH_ENGINE = "searxng";
      SEARXNG_QUERY_URL = "http://127.0.0.1:${toString services.searxng.port}/search?q=<query>";
    };
  };
}
