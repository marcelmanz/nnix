{
  config,
  pkgs,
  services,
  ...
}: {
  services.grafana = {
    enable = true;
    settings = {
      security = {
        secret_key = "$__file{${config.sops.secrets.grafana_secret_key.path}}";
      };
      server = {
        http_addr = "127.0.0.1";
        http_port = services.grafana.port;
        domain = "grafana.marcel.cool";
        root_url = "https://grafana.marcel.cool";
      };
    };
    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          url = "http://127.0.0.1:${toString services.prometheus.port}";
          isDefault = true;
        }
      ];
      dashboards.settings.providers = [
        {
          name = "Local Dashboards";
          options.path = pkgs.runCommand "grafana-dashboards" {} ''
            mkdir -p $out
            cp ${
              pkgs.fetchurl {
                url = "https://grafana.com/api/dashboards/1860/revisions/37/download";
                hash = "sha256-1DE1aaanRHHeCOMWDGdOS1wBXxOF84UXAjJzT5Ek6mM=";
              }
            } $out/node-exporter-full.json
          '';
        }
      ];
    };
  };
  services.prometheus = {
    enable = true;
    port = services.prometheus.port;
    listenAddress = "127.0.0.1";

    exporters = {
      node = {
        enable = true;
        enabledCollectors = ["systemd"];
        port = 9100;
      };
    };

    scrapeConfigs = [
      {
        job_name = "mlab_system";
        static_configs = [
          {
            targets = ["127.0.0.1:${toString config.services.prometheus.exporters.node.port}"];
          }
        ];
      }
    ];
  };
}
