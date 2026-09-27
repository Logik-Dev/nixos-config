_:
let
  metricsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      # Daily export of the last successful full backup per repo, consumed by
      # the node-exporter textfile collector (PgbackrestBackupStale /
      # PgbackrestMetricsMissing alerts). Runs as root: the env file is
      # root-only and root can traverse the postgres-owned repo dirs.
      notify.services = [ "pgbackrest-metrics" ];

      systemd.services.pgbackrest-metrics = {
        description = "Export pgBackRest last-full timestamps for Prometheus";
        startAt = "*-*-* 09:20:00";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          EnvironmentFile = config.age.secrets."pgbackrest.env".path;
        };
        script = ''
          set -euo pipefail
          dir=/var/lib/node-exporter-textfile
          tmp="$dir/.pgbackrest.prom.tmp"
          umask 022
          {
            echo "# HELP pgbackrest_last_full_timestamp_seconds Timestamp of the last successful full backup (epoch seconds)"
            echo "# TYPE pgbackrest_last_full_timestamp_seconds gauge"
            ${lib.getExe pkgs.pgbackrest} --stanza=default info --output=json \
              | ${lib.getExe pkgs.jq} -r '
                [ .[] | .name as $stanza
                  | .backup[]?
                  | select(.type == "full" and (.error | not))
                  | { stanza: $stanza,
                      repo: (.database."repo-key" | tostring),
                      ts: .timestamp.stop } ]
                | group_by(.repo)[]
                | "pgbackrest_last_full_timestamp_seconds{stanza=\"\(.[0].stanza)\",repo=\"\(.[0].repo)\"} \(map(.ts) | max)"
              '
            echo "# HELP pgbackrest_spool_size_bytes Current size of the async archive-push spool"
            echo "# TYPE pgbackrest_spool_size_bytes gauge"
            echo "pgbackrest_spool_size_bytes $(${pkgs.coreutils}/bin/du -sb /var/spool/pgbackrest | ${pkgs.coreutils}/bin/cut -f1)"
          } > "$tmp"
          mv -f "$tmp" "$dir/pgbackrest.prom"
        '';
      };
    };
in
{
  flake.modules.nixos.pgbackrest.imports = [ metricsModule ];
}
