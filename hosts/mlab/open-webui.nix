{
  config,
  inputs,
  services,
  ...
}: let
  synthetic = (builtins.fromJSON (builtins.readFile "${inputs.dots}/.pi/agent/models.json")).providers.synthetic;
  hfRouter = "https://router.huggingface.co";
in {
  sops.secrets."hf_token" = {};

  sops.templates."open-webui.env".content = ''
    OPENAI_API_KEYS=${config.sops.placeholder.synthetic_api_key};${config.sops.placeholder.hf_token}
    IMAGES_OPENAI_API_KEY=${config.sops.placeholder.hf_token}
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
      OPENAI_API_BASE_URLS = "${synthetic.baseUrl};${hfRouter}/v1";
      OPENAI_API_CONFIGS = builtins.toJSON {
        "0" = {
          enable = true;
          model_ids = map (model: model.id) synthetic.models;
        };
        # no model_ids: every model the hf router serves shows up on its own,
        # so a new one needs no rebuild, just the picker search.
        "1" = {
          enable = true;
        };
      };

      # the router only speaks openai images under a provider path, not /v1.
      ENABLE_IMAGE_GENERATION = "True";
      IMAGE_GENERATION_ENGINE = "openai";
      IMAGES_OPENAI_API_BASE_URL = "${hfRouter}/nscale/v1";
      IMAGE_GENERATION_MODEL = "black-forest-labs/FLUX.1-schnell";
      IMAGE_SIZE = "1024x1024";

      ENABLE_WEB_SEARCH = "True";
      WEB_SEARCH_ENGINE = "searxng";
      SEARXNG_QUERY_URL = "http://127.0.0.1:${toString services.searxng.port}/search?q=<query>";
    };
  };
}
