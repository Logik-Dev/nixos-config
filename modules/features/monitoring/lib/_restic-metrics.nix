{ pkgs }:
# Push-based restic metrics. Sourced by the per-source backup unit (after a
# successful backup) so node_exporter's textfile collector picks them up.
# Replaces the 56 polling prometheus-restic-exporter services (one per repo),
# which hammered the Hetzner Storage Box over sftp and tripped its per-IP
# rate-limiter / ban. Metric names and the `repository="<source>-<target>"`
# label are kept identical so the Grafana dashboard and the alert rules keep
# working unchanged.
pkgs.writeText "restic-metrics.sh" ''
  emit_restic_metrics() {
    src="$1"; key="$2"; repo="$3"
    dir=/var/lib/node-exporter-textfile
    file="$dir/restic-$src-$key.prom"
    tmp="$file.tmp"
    now="$(date +%s)"
    count="$(restic -r "$repo" snapshots --json 2>/dev/null | ${pkgs.jq}/bin/jq 'length' 2>/dev/null || echo 0)"
    size="$(restic -r "$repo" stats --json 2>/dev/null | ${pkgs.jq}/bin/jq '.total_size // 0' 2>/dev/null || echo 0)"
    case "$count" in "" | *[!0-9]*) count=0 ;; esac
    case "$size" in "" | *[!0-9]*) size=0 ;; esac
    {
      printf 'restic_backup_timestamp{repository="%s-%s"} %s\n' "$src" "$key" "$now"
      printf 'restic_snapshots_total{repository="%s-%s"} %s\n' "$src" "$key" "$count"
      printf 'restic_backup_size_total{repository="%s-%s"} %s\n' "$src" "$key" "$size"
    } > "$tmp"
    mv -f "$tmp" "$file"
  }
''
