{ ... }:
{
  flake.modules.nixos.prometheus.imports = [
    {
      services.prometheus.rules = [
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
                  expr = ''(node_filesystem_size_bytes{mountpoint!~".*(.gvfs|dock.*|containerd.*)"} - node_filesystem_avail_bytes{mountpoint!~".*(.gvfs|dock.*|containerd.*)"}) / node_filesystem_size_bytes{mountpoint!~".*(.gvfs|dock.*|containerd.*)"} > 0.80'';
                  for = "5m";
                  labels.severity = "warning";
                  annotations = {
                    summary = "Disk usage > 80% on {{ $labels.mountpoint }}";
                    description = "Filesystem {{ $labels.mountpoint }} on {{ $labels.instance }} is above 80% capacity.";
                  };
                }
                {
                  alert = "HighCpuLoad";
                  # node_cpu_info has no "mode" label — the previous selector
                  # matched nothing, so the division was empty and the alert
                  # could never fire. Count cores from node_cpu_seconds_total;
                  # scalar() is required because count() drops the instance/job
                  # labels that vector division would otherwise match on.
                  expr = ''node_load1 / scalar(count(count by (cpu) (node_cpu_seconds_total{mode="idle"}))) > 4'';
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
                {
                  # A dead exporter silently disables ResticBackupStale /
                  # ResticCheckFailed (absent metrics never fire), so target
                  # health needs its own alert. This replaces the old
                  # notify-failure hook on the exporter units, which fired a
                  # push on EVERY crash-restart cycle — a dozen sftp
                  # exporters in a restart loop during a Storage Box outage
                  # flooded ntfy. Alertmanager groups this into one
                  # notification instead.
                  alert = "ResticExporterDown";
                  expr = ''up{job="restic"} == 0'';
                  for = "30m";
                  labels.severity = "warning";
                  annotations = {
                    summary = "Restic exporter down: {{ $labels.repository }}";
                    description = "The restic exporter for {{ $labels.repository }} has been unreachable for 30 minutes — its staleness/check alerts are blind until it returns.";
                  };
                }
              ];
            }
          ];
        })
      ];
    }
  ];
}
