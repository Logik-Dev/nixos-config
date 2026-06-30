{ ... }:
{
  flake.modules.nixos.postgres = {
    services.prometheus.exporters.postgres = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9187;
      runAsLocalSuperUser = true;
      dataSourceName = "host=/run/postgresql dbname=postgres user=postgres sslmode=disable";
      extraFlags = [
        "--collector.database"
        "--collector.replication_slot"
        "--collector.pg_long_running_transactions"
        "--collector.pg_stat_activity"
      ];
    };

    services.postgresql.ensureUsers = [
      {
        name = "prometheus";
        ensureClauses.SUPERUSER = true;
      }
    ];

    notify.services = [ "prometheus-postgres-exporter" ];
  };
}
