{ ... }:
{
  flake.modules.nixos.postgres =
    {
      config,
      pkgs,
      ...
    }:
    {
      services.prometheus.exporters.postgres = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = 9187;
        runAsLocalSuperUser = true;
        dataSourceName = "host=/run/postgresql dbname=postgres user=postgres sslmode=disable";
        extraFlags = [
          "--collector.database"
          "--collector.replication_slots"
          "--collector.long_running_transactions"
          "--collector.stat_activity_autovacuum"
        ];
      };

      # The old `prometheus` role (SUPERUSER, LOGIN) is unused: the exporter
      # connects as the postgres superuser (runAsLocalSuperUser). Demote and
      # lock it — idempotent, after postgresql-setup on every boot.
      systemd.services.postgresql-setup.serviceConfig.ExecStartPost = [
        (pkgs.writeShellScript "postgres-prometheus-demote" ''
          set -euo pipefail
          ${config.services.postgresql.finalPackage}/bin/psql -d postgres -v ON_ERROR_STOP=1 <<'SQL'
          DO $$
          BEGIN
            IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'prometheus') THEN
              ALTER ROLE prometheus NOSUPERUSER NOLOGIN;
            END IF;
          END
          $$;
          SQL
        '')
      ];

      notify.services = [ "prometheus-postgres-exporter" ];
    };
}
