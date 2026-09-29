_: {
  flake.modules.nixos.cgroup-pressure =
    { lib, pkgs, ... }:
    let
      # The cgroups whose PSI is worth a metric. Deliberately short: PSI is
      # per-cgroup and cheap to read, but a label per unit on a 40-service host
      # would bury the signal. Two groups, and the comparison between them *is*
      # the measurement:
      #
      #  - victims — what BFQ + the ionice knobs are supposed to protect. Their
      #    io pressure must go DOWN during the batch windows.
      #  - batch — what pays for it. Its io pressure must go UP: that is BFQ
      #    making it wait, which is the whole point.
      #
      # This is the instrument the C3 gate was missing. `node_pressure_io_*` is
      # host-wide and counts *any* task stalled on IO, snapraid included, so it
      # rises when BFQ works as intended — it cannot tell the two groups apart
      # (docs/resource-control-plan.md §C3, révision 4).
      watched = [
        # victims
        "system.slice/jellyfin.service"
        "system.slice/postgresql.service"
        "system.slice/system-immich.slice"
        "system.slice/system-paperless.slice"
        "machine.slice" # the Home Assistant VM
        # batch — cgroups that only exist while the oneshot runs, which is
        # exactly the window we care about; absent files are skipped silently.
        "system.slice/snapraid-sync.service"
        "system.slice/restic-backups-*.service"
        "system.slice/nix-daemon.service"
      ];
    in
    {
      # A sampling loop rather than the repo's usual oneshot+timer (vpn-monitor,
      # pgbackrest-metrics): those run every 5 min or daily, while a 30 min
      # snapraid window needs a resolution comparable to the host-wide metric it
      # is being compared against. A per-30s timer would mean ~2880 unit
      # invocations a day in the journal and a cgroup churn of its own; one
      # long-running reader is quieter and costs a single awk per cycle.
      systemd.services.cgroup-pressure-metrics = {
        description = "Export per-cgroup PSI stall counters for Prometheus";
        wantedBy = [ "multi-user.target" ];
        after = [ "prometheus-node-exporter.service" ];
        path = with pkgs; [
          coreutils
          gawk
        ];
        serviceConfig = {
          Type = "simple";
          Restart = "on-failure";
          RestartSec = "30s";
          # 5 failures inside 5 min leaves the unit in `failed` instead of
          # retrying forever — that is what makes SystemdUnitFailed able to fire
          # (notify.services below puts it in node.nix's unit-include regex).
          StartLimitIntervalSec = "5min";
          StartLimitBurst = 5;

          ProtectSystem = "strict";
          ReadWritePaths = [ "/var/lib/node-exporter-textfile" ];
          ProtectHome = true;
          # Read-only /sys/fs/cgroup is exactly what this needs.
          ProtectControlGroups = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          PrivateTmp = true;
          PrivateNetwork = true;
          NoNewPrivileges = true;
          RestrictAddressFamilies = [ "AF_UNIX" ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          MemoryDenyWriteExecute = true;
          LockPersonality = true;
          SystemCallFilter = [
            "@system-service"
            "~@privileged"
            "~@resources"
          ];
          SystemCallArchitectures = "native";
        };
        script = ''
          # `set +e` first: NixOS prepends its own `set -e`, and a cgroup that
          # disappears mid-cycle (a oneshot finishing) must not kill the sampler.
          # Same reasoning as vpn-monitor.
          set +e

          dir=/var/lib/node-exporter-textfile
          file="$dir/cgroup-pressure.prom"
          umask 022

          patterns=( ${lib.escapeShellArgs watched} )

          while :; do
            files=()
            for pat in "''${patterns[@]}"; do
              # Unquoted on purpose: this is where the globs expand. A pattern
              # that matches nothing stays literal and is dropped by the -r test.
              for cg in /sys/fs/cgroup/$pat; do
                for res in io cpu memory; do
                  [ -r "$cg/$res.pressure" ] && files+=( "$cg/$res.pressure" )
                done
              done
            done

            tmp="$file.tmp"
            {
              # One awk for the whole cycle. Output is buffered per metric family
              # so every sample of a family is contiguous and preceded by its own
              # HELP/TYPE — the textfile collector's parser wants that, and the
              # natural loop order here interleaves families.
              [ ''${#files[@]} -gt 0 ] && awk '
                FNR == 1 {
                  n = split(FILENAME, p, "/")
                  res = p[n]; sub(/\.pressure$/, "", res)
                  cg = p[n - 1]
                }
                $1 == "some" || $1 == "full" {
                  total = ""
                  for (i = 2; i <= NF; i++)
                    if (split($i, kv, "=") == 2 && kv[1] == "total") total = kv[2]
                  if (total == "") next
                  # Mirrors node_exporter: "some" → waiting, "full" → stalled.
                  kind = ($1 == "some") ? "waiting" : "stalled"
                  name = "cgroup_pressure_" res "_" kind "_seconds_total"
                  help[name] = ($1 == "some") \
                    ? "Total time at least one task in this cgroup was stalled on " res " (PSI some, seconds)." \
                    : "Total time every runnable task in this cgroup was stalled on " res " (PSI full, seconds)."
                  # PSI totals are microseconds since the cgroup was created, so
                  # they reset when a unit restarts. Exported as a counter on
                  # purpose: rate() handles the reset, and rate() of this is the
                  # fraction of wall time stalled — directly comparable to
                  # node_pressure_io_waiting_seconds_total.
                  out[name] = out[name] sprintf("%s{cgroup=\"%s\"} %.6f\n", name, cg, total / 1000000)
                }
                END {
                  for (name in out) {
                    printf "# HELP %s %s\n", name, help[name]
                    printf "# TYPE %s counter\n", name
                    printf "%s", out[name]
                  }
                }
              ' "''${files[@]}"

              # Staleness heartbeat, same idiom as vpn_monitor_timestamp_seconds:
              # a wedged loop keeps a readable .prom file with frozen counters,
              # which rate() reports as a flat zero rather than as an outage.
              echo "# HELP cgroup_pressure_scrape_timestamp_seconds Unix time of the last successful sampling cycle."
              echo "# TYPE cgroup_pressure_scrape_timestamp_seconds gauge"
              echo "cgroup_pressure_scrape_timestamp_seconds $(date +%s)"
              echo "# HELP cgroup_pressure_cgroups Number of cgroup PSI files read in the last cycle."
              echo "# TYPE cgroup_pressure_cgroups gauge"
              echo "cgroup_pressure_cgroups ''${#files[@]}"
            } > "$tmp"
            mv -f "$tmp" "$file"

            sleep 30
          done
        '';
      };

      notify.services = [ "cgroup-pressure-metrics" ];
    };
}
