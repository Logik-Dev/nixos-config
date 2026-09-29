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
                    # Resource-control tripwire (docs/resource-control-plan.md, C5).
                    # hyper has no cgroup limits at all: the kernel OOM killer is
                    # the only backstop and it does not distinguish Postgres from
                    # a restic job. Baseline measured over 7 days: exactly zero
                    # kills, which is why the plan deliberately stops at alerting
                    # instead of imposing MemoryMax caps. A single kill is the
                    # signal that the slices+limits spec (plan annexe A) is needed.
                    alert = "HostOOMKill";
                    expr = "increase(node_vmstat_oom_kill[15m]) > 0";
                    labels.severity = "critical";
                    annotations = {
                      summary = "Kernel OOM killer fired on {{ $labels.instance }}";
                      description = "The kernel killed at least one process for memory in the last 15 minutes. Nothing on this host protects critical services from the global OOM killer — identify the victim with `journalctl -k --grep oom` and see docs/resource-control-plan.md annexe A.";
                    };
                  }
                  {
                    # PSI, not free memory: this is the fraction of wall time at
                    # least one task spent stalled waiting on memory reclaim.
                    # Distinct from HighMemoryPressure above, which only watches
                    # MemAvailable and stays quiet while the kernel thrashes to
                    # keep it high. Threshold is ~7x the measured 7-day peak
                    # (0.014), so it reports a regime change, not normal load.
                    alert = "MemoryStallSustained";
                    expr = "rate(node_pressure_memory_waiting_seconds_total[10m]) > 0.1";
                    for = "15m";
                    labels.severity = "warning";
                    annotations = {
                      summary = "Sustained memory stalls on {{ $labels.instance }}";
                      description = "Tasks have been stalling on memory reclaim for 15 minutes (PSI some/avg > 10%, measured 7-day peak was 1.4%). Check /proc/pressure/memory and `systemd-cgtop -m`.";
                    };
                  }
                  {
                    # IO is the contention that actually exists on this host:
                    # 7-day peak 0.51, in bursts at 01-02h (restic window) and
                    # 10h (snapraid-sync, 340 GB read). Those bursts are brief, so
                    # the alert deliberately requires a 30-minute plateau — it
                    # fires on a batch job that stopped yielding, not on the
                    # nightly window doing its job.
                    alert = "IoStallSustained";
                    expr = "rate(node_pressure_io_waiting_seconds_total[10m]) > 0.4";
                    for = "30m";
                    labels.severity = "warning";
                    annotations = {
                      summary = "Sustained IO stalls on {{ $labels.instance }}";
                      description = "Tasks have been stalling on IO for 30 minutes (PSI some/avg > 40%). Expected sources are the restic window and snapraid-sync; a plateau means one is not yielding. See docs/resource-control-plan.md C3.";
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
                    # The alert channel watching itself. _ntfy.nix retries a
                    # publish for ~28 s then spools to disk; anything still
                    # pending after 15 minutes means notifications are being
                    # held, i.e. a real failure may have gone unseen — which is
                    # exactly what happened on 2026-09-28 (cf-ddns, lost without
                    # a trace, docs/notifications-plan.md §2.1).
                    #
                    # This is deliberately routed through a *different* publisher
                    # (Prometheus -> Alertmanager -> alertmanager-ntfy) than the
                    # one being reported on. If ntfy itself is the thing that is
                    # down, this alert cannot be delivered either — it then
                    # arrives with the spool once ntfy is back, and stays visible
                    # in Grafana/Glance in the meantime.
                    alert = "NtfySpoolStuck";
                    expr = "ntfy_spool_pending > 0";
                    for = "15m";
                    labels.severity = "critical";
                    annotations = {
                      summary = "Notifications ntfy bloquées en attente";
                      description = "{{ $value }} notification(s) attendent d'être publiées depuis plus de 15 minutes (la plus ancienne : {{ with query \"ntfy_spool_oldest_age_seconds\" }}{{ . | first | value | humanizeDuration }}{{ end }}). Une panne réelle peut être passée inaperçue. Voir /var/lib/ntfy-spool et `journalctl -u ntfy-spool-drain`.";
                    };
                  }
                  {
                    # Staleness, not absent(): the textfile collector keeps
                    # serving the last .prom forever, so a drain that stopped
                    # running would leave `ntfy_spool_pending 0` exposed and
                    # looking healthy for good (cf. VpnMonitorMissing).
                    alert = "NtfySpoolDrainMissing";
                    expr = "absent(ntfy_spool_drain_timestamp_seconds) or (time() - ntfy_spool_drain_timestamp_seconds > 900)";
                    for = "10m";
                    labels.severity = "warning";
                    annotations = {
                      summary = "Le drain du spool ntfy ne rapporte plus";
                      description = "ntfy_spool_drain_timestamp_seconds est absent ou vieux de plus de 15 minutes — ntfy-spool-drain.timer (2 min) s'est arrêté, ce qui laisserait NtfySpoolStuck lire une valeur figée et les notifications en attente non rejouées.";
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
                  # `node_hwmon_temp_celsius > 75` across every sensor was, on its
                  # own, 100 % of the Alertmanager notification volume: all 34
                  # messages in the 12-hour ntfy cache were TemperatureHigh. Two
                  # independent defects (docs/notifications-plan.md §0.5):
                  #
                  #  - PER SENSOR. coretemp exposes 9 series (package + cores);
                  #    each crossed and re-crossed 75 °C on its own, so one
                  #    thermal episode produced up to 9 alerts, each with its own
                  #    firing/resolved pair.
                  #  - ONE THRESHOLD FOR EVERY CHIP. 75 °C is routine load for an
                  #    i7-9700K (7-day median 58 °C, 1041 minutes above 75) and at
                  #    the same time far too permissive for an NVMe, which
                  #    throttles around 80 °C.
                  #
                  # `max by (chip)` collapses an episode to one alert per chip, and
                  # `keep_firing_for` stops the oscillation around the threshold
                  # from producing a resolved/firing pair every few minutes
                  # (Prometheus 3.14 here, the field needs >= 2.42).
                  #
                  # Thresholds sized on 7 days of local history, so both still fire
                  # for real episodes: coretemp spent 323 minutes above 90 °C
                  # (7-day peak 100 °C = Tjunction, i.e. the CPU does throttle),
                  # the NVMes 69 minutes above 85 °C (peak 89.9 °C).
                  {
                    alert = "CpuTemperatureHigh";
                    expr = ''max by (chip) (node_hwmon_temp_celsius{chip=~"platform_coretemp.*|thermal_.*"}) > 90'';
                    for = "10m";
                    keep_firing_for = "30m";
                    labels.severity = "warning";
                    annotations = {
                      summary = "CPU temperature above 90 °C ({{ $labels.chip }})";
                      description = "{{ $labels.chip }} has been above 90 °C for 10 minutes (hottest sensor: {{ $value }} °C). Tjunction on this i7-9700K is 100 °C, which the 7-day history does reach — check the cooling, not just the alert.";
                    };
                  }
                  {
                    alert = "NvmeTemperatureHigh";
                    expr = ''max by (chip) (node_hwmon_temp_celsius{chip=~"nvme.*"}) > 85'';
                    for = "10m";
                    keep_firing_for = "30m";
                    labels.severity = "warning";
                    annotations = {
                      summary = "NVMe temperature above 85 °C ({{ $labels.chip }})";
                      description = "{{ $labels.chip }} has been above 85 °C for 10 minutes ({{ $value }} °C). NVMe drives throttle around 80 °C and shorten their life well before the critical limit.";
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
                    # MON-11. La panne qu'on a vécue : Home Assistant a disparu
                    # du courtier le 2026-09-27 et n'est pas revenu à travers six
                    # redémarrages de mosquitto (P0-9). L'unité du courtier n'a
                    # jamais échoué, donc ni SystemdUnitFailed ni notify-failure
                    # n'avaient quoi que ce soit à dire, et tout le Zigbee est
                    # resté muet 2,5 jours.
                    #
                    # Une seule règle pour tous les clients : le relevé émet un 0
                    # explicite pour chaque client *attendu* qui manque, et
                    # l'étiquette `client` dit lequel. Alerter sur une absence
                    # suppose de connaître la liste attendue — d'où cette liste
                    # en dur dans mqtt-clients.nix plutôt qu'une déduction à
                    # partir des connexions observées.
                    #
                    # `warning` et non `critical` : le courtier va bien, c'est
                    # une condition côté client qui se répare souvent d'elle-même
                    # au redémarrage du service. 15 min encaissent les
                    # reconnexions normales — y compris celles qui suivent le
                    # passage restic de mosquitto.
                    alert = "MqttClientDisconnected";
                    expr = "mqtt_client_connected == 0";
                    for = "15m";
                    labels.severity = "warning";
                    annotations = {
                      summary = "MQTT client {{ $labels.client }} disconnected from the broker";
                      description = "{{ $labels.client }} holds no connection to mosquitto. The broker unit can be perfectly healthy while this is true — that is exactly how Home Assistant stayed silently disconnected for 2.5 days (P0-9). Check the client, not the broker.";
                    };
                  }
                  {
                    # Interrupteur d'homme mort, même raison que VpnMonitorMissing :
                    # le collecteur textfile sert un .prom pour toujours, donc un
                    # relevé arrêté laisse des valeurs figées qui paraissent
                    # saines — `absent()` seul ne se déclencherait jamais.
                    alert = "MqttMonitorMissing";
                    expr = "absent(mqtt_monitor_timestamp_seconds) or (time() - mqtt_monitor_timestamp_seconds > 1800)";
                    for = "10m";
                    labels.severity = "warning";
                    annotations = {
                      summary = "MQTT client monitor not reporting";
                      description = "mqtt_monitor_timestamp_seconds is missing or older than 30 minutes — mqtt-monitor.timer may have stopped, which would leave MqttClientDisconnected reading frozen values.";
                    };
                  }
                  {
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
