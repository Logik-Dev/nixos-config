_: {
  flake.modules.nixos.prometheus.imports = [
    (
      {
        config,
        lib,
        ...
      }:
      let
        # The backups emit one restic_backup_timestamp per (source × target); every
        # source has the two usb + hetzner targets. If fewer series show up, at least
        # one backup unit stopped running entirely — the per-repository staleness
        # alert cannot see a metric that was never written.
        expectedResticMetrics = 2 * (lib.length (lib.attrNames config.backups.sources));
      in
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
                    # Authelia exposes request counters by status code and method.
                    # Only non-GET requests count: the forward-auth/probe traffic
                    # from Traefik+blackbox is GET and returns 401 for protected
                    # vhosts on every scrape, which would otherwise fire this
                    # constantly. Login/credential-stuffing attempts are POST.
                    alert = "AutheliaAuthFailureSpike";
                    expr = ''sum(rate(authelia_request{code=~"401|403",method!="GET"}[10m])) > 0.2'';
                    for = "10m";
                    labels.severity = "warning";
                    annotations = {
                      summary = "Authelia authentication failures";
                      description = "Sustained failed Authelia login attempts (>2/min for 10m) — possible brute-force.";
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
                    # 02:05 + up to 5h random delay). Metrics are pushed by the
                    # backup unit itself (no exporter).
                    alert = "ResticRepoEmpty";
                    expr = "restic_snapshots_total == 0";
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
                    # Push metrics: a backup unit that never runs writes nothing,
                    # so per-repository staleness stays silent. Count the series
                    # and alert when some are missing (dead-man switch).
                    alert = "ResticMetricsMissing";
                    expr = "count(restic_backup_timestamp) < ${toString expectedResticMetrics}";
                    for = "26h";
                    labels.severity = "warning";
                    annotations = {
                      summary = "Restic backup metrics missing";
                      description = "Fewer than ${toString expectedResticMetrics} restic repositories reported a backup timestamp — a backup unit may have stopped running.";
                    };
                  }
                  {
                    # The VPN tunnel is fail-closed by construction, so an outage
                    # leaks nothing — and is therefore completely silent: the
                    # download stack just stops working. Worse, the failure that
                    # actually happened (systemd deleting wireguard-wg0's start
                    # job to break an ordering cycle) leaves **no failed unit**,
                    # so onFailure/notify could not have caught it either.
                    # Handshake timestamp is 0 when wg0 does not exist at all.
                    alert = "VpnTunnelDown";
                    expr = "time() - vpn_tunnel_handshake_timestamp_seconds > 300";
                    for = "10m";
                    labels.severity = "critical";
                    annotations = {
                      summary = "VPN torrent tunnel down";
                      description = "No WireGuard handshake for over 5 minutes (0 = wg0 absent). The download stack is fail-closed, so nothing leaks, but nothing downloads either. Check `journalctl -b` for \"ordering cycle\" and `systemctl status wireguard-wg0 netns-vpn`.";
                    };
                  }
                  {
                    # Ground truth rather than a proxy: the namespace must not exit
                    # through the host's WAN address. Gated on the check having
                    # succeeded so a flaky third party cannot page anyone.
                    alert = "VpnTrafficLeak";
                    expr = "vpn_exit_ip_check_success == 1 and vpn_exit_ip_isolated == 0";
                    for = "5m";
                    labels.severity = "critical";
                    annotations = {
                      summary = "VPN leak: torrent traffic exits through the WAN";
                      description = "The VPN namespace reports the same public IP as the host. Isolation is broken — stop qbittorrent and investigate the namespace routing before anything else.";
                    };
                  }
                  {
                    # qBittorrent binds per address at start-up and never re-binds:
                    # a recreated wg0 leaves it listening on lo/veth only, the
                    # forwarded port unreachable and the ratio at zero — silently.
                    alert = "VpnListenerUnbound";
                    expr = "vpn_tunnel_listener_bound == 0";
                    for = "15m";
                    labels.severity = "warning";
                    annotations = {
                      summary = "qBittorrent not listening on the tunnel";
                      description = "No listener bound to wg0 for the forwarded port: peers cannot reach it and the ratio is going to zero. Usually fixed by `systemctl restart qbittorrent`; it should have been automatic via partOf/wantedBy on wireguard-wg0.";
                    };
                  }
                  {
                    # Dead-man switch: every alert above reads a metric the monitor
                    # writes, so a monitor that stopped running would make them all
                    # silently un-evaluable.
                    #
                    # Staleness, NOT `absent()` alone: node_exporter's textfile
                    # collector keeps serving a .prom file forever, so a monitor
                    # that crashed leaves its last values exposed and looking
                    # healthy indefinitely — `absent()` would never fire. The
                    # timestamp the monitor writes on every run is the only thing
                    # that can distinguish fresh from frozen.
                    alert = "VpnMonitorMissing";
                    expr = "absent(vpn_monitor_timestamp_seconds) or (time() - vpn_monitor_timestamp_seconds > 1800)";
                    for = "10m";
                    labels.severity = "warning";
                    annotations = {
                      summary = "VPN monitor not reporting";
                      description = "vpn_monitor_timestamp_seconds is missing or older than 30 minutes — vpn-monitor.timer may have stopped or the script may be crashing, which would leave every other VPN alert reading frozen values.";
                    };
                  }
                  {
                    # The gap every other VPN/torrent alert left open: they all
                    # check *reachability*, and all of them stayed green while the
                    # upload ceiling sat at 10 KiB/s for days because the
                    # alternative speed limits had been toggled on by hand with the
                    # scheduler off. Nothing failed; the ratio just went to 0.03.
                    #
                    # Alerts on the *outcome* — a crippled ceiling — not on the
                    # mechanism, so a stray turtle click, a bad up_limit and a
                    # mis-set scheduler window are all caught by this one rule.
                    #
                    # The `> 0` half is load-bearing: qBittorrent reports 0 for
                    # *unlimited*, so a bare `< 1048576` would fire permanently on
                    # a perfectly healthy uncapped client. 30m of `for` rides out
                    # the scheduler's own transitions at 02:00 and 07:00.
                    alert = "QbittorrentUploadThrottled";
                    expr = "qbt_up_limit_effective_bytes > 0 and qbt_up_limit_effective_bytes < 1048576";
                    for = "30m";
                    labels.severity = "warning";
                    annotations = {
                      summary = "qBittorrent upload ceiling crippled";
                      description = "The effective upload limit is under 1 MB/s ({{ $value }} B/s) — the ratio is going nowhere and nothing else will report it. Check the turtle icon (alternative speed limits) and the scheduler window in Options -> Speed.";
                    };
                  }
                  {
                    # The throttle alert above reads a metric that only exists if
                    # the scrape worked; a failing login would make it silently
                    # un-evaluable while the stale .prom still looked healthy.
                    alert = "QbittorrentScrapeFailing";
                    expr = "qbt_scrape_success == 0";
                    for = "30m";
                    labels.severity = "warning";
                    annotations = {
                      summary = "qBittorrent API scrape failing";
                      description = "qbittorrent-monitor cannot read the WebUI API (credentials in the cross-seed secret, or the WebUI is down). The upload-ceiling alert cannot be evaluated while this is firing.";
                    };
                  }
                  {
                    # Dead-man switch, same rationale as VpnMonitorMissing: the
                    # textfile collector keeps serving a .prom forever, so a
                    # monitor that stopped running leaves its last values exposed
                    # and looking healthy — absent() alone would never fire.
                    alert = "QbittorrentMonitorMissing";
                    expr = "absent(qbt_monitor_timestamp_seconds) or (time() - qbt_monitor_timestamp_seconds > 1800)";
                    for = "10m";
                    labels.severity = "warning";
                    annotations = {
                      summary = "qBittorrent monitor not reporting";
                      description = "qbt_monitor_timestamp_seconds is missing or older than 30 minutes — qbittorrent-monitor.timer may have stopped, which would leave the upload-ceiling alert reading frozen values.";
                    };
                  }
                ];
              }
            ];
          })
        ];
      }
    )
  ];
}
