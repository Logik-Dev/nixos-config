{ config, ... }:
{
  flake.modules.nixos.prometheus =
    { config, ... }:
    let
      host = config.networking.hostName;
      domain = config.constants.domain;
      traefikServices = builtins.attrNames config.traefik.services;
    in
    {
      services.prometheus = {
        enable = true;
        port = 9090;
        listenAddress = "127.0.0.1";
        stateDir = "prometheus";
        retentionTime = "30d";

        scrapeConfigs = [
          {
            job_name = "node";
            scrape_interval = "15s";
            static_configs = [ { targets = [ "127.0.0.1:9100" ]; } ];
          }
          {
            job_name = "postgres";
            scrape_interval = "15s";
            static_configs = [ { targets = [ "127.0.0.1:9187" ]; } ];
          }
          {
            job_name = "nvidia-gpu";
            scrape_interval = "15s";
            static_configs = [ { targets = [ "127.0.0.1:9835" ]; } ];
          }
          {
            job_name = "restic-s3";
            scrape_interval = "60s";
            static_configs = [
              {
                targets = [ "127.0.0.1:9753" ];
                labels = {
                  repository = "s3";
                };
              }
            ];
          }
          {
            job_name = "restic-usb";
            scrape_interval = "60s";
            static_configs = [
              {
                targets = [ "127.0.0.1:9754" ];
                labels = {
                  repository = "usb";
                };
              }
            ];
          }
          {
            job_name = "blackbox_http";
            scrape_interval = "30s";
            metrics_path = "/probe";
            params = {
              module = [ "http_2xx" ];
            };
            static_configs = [
              {
                targets = map (s: "https://${s}.${host}.${domain}") traefikServices;
              }
            ];
            relabel_configs = [
              {
                source_labels = [ "__address__" ];
                target_label = "__param_target";
              }
              {
                source_labels = [ "__param_target" ];
                target_label = "service";
                regex = "https://([^.]+)\\..*";
              }
              {
                target_label = "__address__";
                replacement = "127.0.0.1:9115";
              }
            ];
          }
        ];

        alertmanagers = [
          {
            static_configs = [ { targets = [ "127.0.0.1:9093" ]; } ];
          }
        ];

        rules = [
          (builtins.toJSON {
            groups = [
              {
                name = "homelab";
                rules = [
                  {
                    alert = "ServiceDown";
                    expr = "up == 0";
                    for = "1m";
                    labels.severity = "critical";
                    annotations = {
                      summary = "Service {{ $labels.job }} down";
                      description = "Prometheus target {{ $labels.instance }} (job: {{ $labels.job }}) has been down for more than 1 minute.";
                    };
                  }
                  {
                    alert = "HighDiskUsage";
                    expr = "(node_filesystem_size_bytes{{mountpoint!~\".*(.gvfs|dock.*|containerd.*)\"}} - node_filesystem_avail_bytes{{mountpoint!~\".*(.gvfs|dock.*|containerd.*)\"}}) / node_filesystem_size_bytes{{mountpoint!~\".*(.gvfs|dock.*|containerd.*)\"}} > 0.80";
                    for = "5m";
                    labels.severity = "warning";
                    annotations = {
                      summary = "Disk usage > 80% on {{ $labels.mountpoint }}";
                      description = "Filesystem {{ $labels.mountpoint }} on {{ $labels.instance }} is above 80% capacity.";
                    };
                  }
                  {
                    alert = "HighCpuLoad";
                    expr = ''node_load1 / count(node_cpu_info{mode="idle"}) > 4'';
                    for = "10m";
                    labels.severity = "warning";
                    annotations = {
                      summary = "High CPU load on {{ $labels.instance }}";
                      description = "CPU load average (1m) is above 4x cores for 10 minutes.";
                    };
                  }
                  {
                    alert = "HighMemoryPressure";
                    expr = "node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < 0.10";
                    for = "5m";
                    labels.severity = "warning";
                    annotations = {
                      summary = "Low memory on {{ $labels.instance }}";
                      description = "Available memory is below 10% for 5 minutes.";
                    };
                  }
                  {
                    alert = "ResticBackupStale";
                    expr = "time() - restic_backup_timestamp > 172800";
                    for = "0m";
                    labels.severity = "warning";
                    annotations = {
                      summary = "Restic backup stale on {{ $labels.repository }}";
                      description = "No successful restic backup in the last 48 hours for repository {{ $labels.repository }}.";
                    };
                  }
                  {
                    alert = "ResticCheckFailed";
                    expr = "restic_check_success == 0";
                    for = "5m";
                    labels.severity = "critical";
                    annotations = {
                      summary = "Restic check failed for {{ $labels.repository }}";
                      description = "Restic repository check failed for {{ $labels.repository }}.";
                    };
                  }
                ];
              }
            ];
          })
        ];
      };

      notify.services = [ "prometheus" ];
    };
}
