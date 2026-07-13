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
        enabledCollectors = ["systemd" "textfile"];
        port = 9100;
        extraFlags = ["--collector.textfile.directory=/var/lib/prometheus-node-exporter-text-files"];
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

  systemd.tmpfiles.rules = [
    "d /var/lib/prometheus-node-exporter-text-files 0755 root root -"
  ];
  systemd.services.directory-size-exporter = {
    description = "Export /var/lib subdir sizes for Prometheus textfile collector";
    serviceConfig.Type = "oneshot";
    script = ''
      DIR=/var/lib/prometheus-node-exporter-text-files
      mkdir -p "$DIR"
      TMP=$(mktemp -p "$DIR")
      du --max-depth=1 -b /var/lib 2>/dev/null | while IFS=$'\t' read -r size path; do
        [ "$path" = "/var/lib" ] && continue
        printf 'node_directory_size_bytes{directory="%s"} %s\n' "$path" "$size"
      done > "$TMP"
      chmod 0644 "$TMP"
      mv "$TMP" "$DIR/dir_sizes.prom"
    '';
  };

  systemd.timers.directory-size-exporter = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "1min";
      OnCalendar = "hourly";
      Persistent = true;
    };
  };
}
