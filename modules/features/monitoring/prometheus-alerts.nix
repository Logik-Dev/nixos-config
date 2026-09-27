_: {
  flake.modules.nixos.prometheus.imports = [
    {
      services.prometheus.rules = [
        (builtins.toJSON {
          groups = [
            {
              name = "homelab";
              rules = [
                {
                  # restic exporter targets are excluded: a Storage Box outage
                  # takes all ~38 sftp exporters down at once, and
                  # ResticExporterDown already reports that calmly after 30m.
                  alert = "ServiceDown";
                  expr = ''up{job!="restic"} == 0'';
                  for = "1m";
                  labels.severity = "critical";
                  annotations = {
                    summary = "Service {{ $labels.job }} down";
                    description = "Prometheus target {{ $labels.instance }} (job: {{ $labels.job }}) has been down for more than 1 minute.";
                  };
                }
                {
                  # Traefik metrics (metrics entrypoint) count requests per
                  # service and status code; a sustained 5xx rate usually means
                  # a backend is broken (or the Authelia portal itself).
                  alert = "TraefikHigh5xxRate";
                  expr = ''sum(rate(traefik_service_requests_total{code=~"5.."}[5m])) > 1'';
                  for = "10m";
                  labels.severity = "warning";
                  annotations = {
                    summary = "Traefik is returning 5xx responses";
                    description = "More than 1 server error/s (5m rate) through Traefik for 10 minutes.";
                  };
                }
                {
                  # Authelia exposes request counters by status code; a sustained
                  # 401/403 rate is a brute-force / credential-stuffing signal.
                  alert = "AutheliaAuthFailureSpike";
                  expr = ''sum(rate(authelia_request{code=~"401|403"}[10m])) > 0.5'';
                  for = "10m";
                  labels.severity = "warning";
                  annotations = {
                    summary = "Authelia authentication failures";
                    description = "More than 5 failed/denied Authelia requests per minute for 10 minutes.";
                  };
                }
                {
                  # f2b_up is the exporter's own view of the fail2ban socket;
                  # the Prometheus target can stay up while the socket is dead.
                  alert = "Fail2banExporterUnhealthy";
                  expr = "f2b_up == 0";
                  for = "15m";
                  labels.severity = "warning";
                  annotations = {
                    summary = "fail2ban exporter cannot reach the daemon";
                    description = "The fail2ban exporter reported f2b_up=0 for 15 minutes — ban metrics are blind.";
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
                  # Authelia-protected vhosts redirect to the portal (2xx/401),
                  # so this mainly covers the unprotected services (Immich,
                  # Jellyfin, Vaultwarden, ntfy) plus Traefik/TLS itself.
                  alert = "ProbeFailure";
                  expr = "probe_success == 0";
                  for = "5m";
                  labels.severity = "critical";
                  annotations = {
                    summary = "Blackbox probe failed for {{ $labels.service }}";
                    description = "{{ $labels.service }} has been failing its HTTP probe for 5 minutes.";
                  };
                }
                {
                  alert = "TLSCertExpirySoon";
                  expr = "probe_ssl_earliest_cert_expiry - time() < 14 * 86400";
                  for = "1h";
                  labels.severity = "warning";
                  annotations = {
                    summary = "TLS certificate for {{ $labels.service }} expires soon";
                    description = "The certificate presented for {{ $labels.service }} expires in less than 14 days.";
                  };
                }
                {
                  alert = "PostgresDown";
                  expr = "pg_up == 0";
                  for = "5m";
                  labels.severity = "critical";
                  annotations = {
                    summary = "PostgreSQL is down";
                    description = "The postgres exporter can no longer reach the local cluster.";
                  };
                }
                {
                  # In async mode pg acknowledges WAL from the spool, so
                  # failed_count can stay quiet; the age of the last successful
                  # archive is the reliable signal.
                  alert = "PgWalArchiveStale";
                  expr = "pg_stat_archiver_last_archive_age > 7200";
                  for = "15m";
                  labels.severity = "warning";
                  annotations = {
                    summary = "WAL archiving is lagging";
                    description = "No WAL segment archived for more than 2 hours — PITR offsite is falling behind.";
                  };
                }
                {
                  alert = "PgWalArchiveFailures";
                  expr = "increase(pg_stat_archiver_failed_count[1h]) > 0";
                  for = "10m";
                  labels.severity = "warning";
                  annotations = {
                    summary = "WAL archiving failures";
                    description = "archive-push failed at least once in the last hour.";
                  };
                }
                {
                  alert = "PgbackrestBackupStale";
                  expr = "time() - pgbackrest_last_full_timestamp_seconds > 8 * 86400";
                  for = "1h";
                  labels.severity = "warning";
                  annotations = {
                    summary = "pgBackRest full backup stale ({{ $labels.stanza }}/repo{{ $labels.repo }})";
                    description = "No successful full backup in the last 8 days for stanza {{ $labels.stanza }}, repo {{ $labels.repo }}.";
                  };
                }
                {
                  # The async spool grows on the root fs while a repo is
                  # unreachable; at 2 GiB pgBackRest starts dropping WAL
                  # (archive-push-queue-max). Catch the growth early.
                  alert = "PgbackrestSpoolGrowing";
                  expr = "pgbackrest_spool_size_bytes > 536870912";
                  for = "1h";
                  labels.severity = "warning";
                  annotations = {
                    summary = "pgBackRest WAL spool growing (> 512 MiB)";
                    description = "archive-push has been queueing WAL for over an hour — offsite archiving may be failing (WAL is dropped at 2 GiB).";
                  };
                }
                {
                  alert = "PgbackrestMetricsMissing";
                  expr = "count(pgbackrest_last_full_timestamp_seconds) < 2";
                  for = "26h";
                  labels.severity = "warning";
                  annotations = {
                    summary = "pgBackRest metrics missing";
                    description = "Fewer than 2 repos reported last-full timestamps — the daily metrics job may have stopped.";
                  };
                }
                {
                  alert = "SystemdUnitFailed";
                  expr = ''node_systemd_unit_state{state="failed"} == 1'';
                  for = "5m";
                  labels.severity = "warning";
                  annotations = {
                    summary = "systemd unit {{ $labels.name }} failed";
                    description = "Unit {{ $labels.name }} has been in the failed state for 5 minutes.";
                  };
                }
                {
                  alert = "TemperatureHigh";
                  expr = "node_hwmon_temp_celsius > 75";
                  for = "10m";
                  labels.severity = "warning";
                  annotations = {
                    summary = "High temperature on {{ $labels.chip }}/{{ $labels.sensor }}";
                    description = "Sensor {{ $labels.chip }}/{{ $labels.sensor }} is above 75 °C for 10 minutes.";
                  };
                }
                {
                  alert = "GpuTemperatureHigh";
                  expr = "nvidia_smi_temperature_gpu > 85";
                  for = "10m";
                  labels.severity = "warning";
                  annotations = {
                    summary = "GPU temperature above 85 °C";
                    description = "The P4000 GPU has been above 85 °C for 10 minutes.";
                  };
                }
                {
                  # A repo with zero snapshots exposes restic_snapshots_total = 0
                  # but no restic_backup_timestamp, so ResticBackupStale can
                  # never fire for it. 26h covers a freshly added source (next
                  # 02:05 + up to 5h random delay).
                  alert = "ResticRepoEmpty";
                  expr = ''restic_snapshots_total{job="restic"} == 0'';
                  for = "26h";
                  labels.severity = "warning";
                  annotations = {
                    summary = "Restic repository empty: {{ $labels.repository }}";
                    description = "Repository {{ $labels.repository }} has never had a snapshot.";
                  };
                }
                {
                  alert = "DrillStale";
                  expr = "time() - drill_last_run_timestamp_seconds > 9 * 86400";
                  for = "30m";
                  labels.severity = "warning";
                  annotations = {
                    summary = "Backup drill {{ $labels.drill }} has not run";
                    description = "The weekly drill {{ $labels.drill }} has not completed in the last 9 days (dead-man switch).";
                  };
                }
                {
                  # Data disks are mounted with `nofail`: a missing mount is
                  # otherwise invisible (tmpfiles recreate the dirs on the root
                  # fs). Jobs now require their mounts (RequiresMountsFor), this
                  # alert reports the root cause.
                  alert = "MountPointMissing";
                  expr = ''absent(node_filesystem_size_bytes{mountpoint="/mnt/usb"})'';
                  for = "5m";
                  labels = {
                    severity = "critical";
                    mountpoint = "/mnt/usb";
                  };
                  annotations = {
                    summary = "Mount point {{ $labels.mountpoint }} is missing";
                    description = "The /mnt/usb filesystem is not mounted — backups would silently write to the root filesystem.";
                  };
                }
                {
                  alert = "MountPointMissing";
                  expr = ''absent(node_filesystem_size_bytes{mountpoint="/mnt/ultra"})'';
                  for = "5m";
                  labels = {
                    severity = "critical";
                    mountpoint = "/mnt/ultra";
                  };
                  annotations = {
                    summary = "Mount point {{ $labels.mountpoint }} is missing";
                    description = "The /mnt/ultra filesystem is not mounted — media data and backup sources are unavailable.";
                  };
                }
                {
                  alert = "FilesystemReadOnly";
                  # /nix/store is a deliberately read-only ext4 mount here.
                  expr = ''node_filesystem_readonly{fstype!~"squashfs|iso9660|erofs|tmpfs|ramfs",mountpoint!="/nix/store"} == 1'';
                  for = "10m";
                  labels.severity = "critical";
                  annotations = {
                    summary = "Filesystem {{ $labels.mountpoint }} is read-only";
                    description = "Filesystem {{ $labels.mountpoint }} on {{ $labels.instance }} is mounted read-only.";
                  };
                }
                {
                  # The exporter exposes restic_backup_timestamp once PER
                  # SNAPSHOT (snapshot_hash label), so a plain
                  # `time() - restic_backup_timestamp` fires for every snapshot
                  # older than 48h — i.e. always. Compare the most recent
                  # snapshot per repository instead.
                  alert = "ResticBackupStale";
                  expr = "time() - max by (repository) (restic_backup_timestamp) > 172800";
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
                  # 75m: sftp exporters deliberately stagger up to 50 min after
                  # a nixos switch (Storage Box rate-limit protection), which
                  # would trip a 30m threshold on every deploy.
                  for = "75m";
                  labels.severity = "warning";
                  annotations = {
                    summary = "Restic exporter down: {{ $labels.repository }}";
                    description = "The restic exporter for {{ $labels.repository }} has been unreachable for 75 minutes — its staleness/check alerts are blind until it returns.";
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
