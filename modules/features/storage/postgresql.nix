{ ... }:
{

  flake.modules.nixos.hyper =
    {
      pkgs,
      commonSecret,
      config,
      ...
    }:
    {
      services.postgresql = {
        enable = true;

        initialScript = pkgs.writeText "ownership.sql" ''
          ALTER DATABASE "sonarr-main" OWNER TO sonarr;
          ALTER DATABASE "sonarr-logs" OWNER TO sonarr;
          ALTER DATABASE "radarr-main" OWNER TO radarr;
          ALTER DATABASE "radarr-logs" OWNER TO radarr;
          ALTER DATABASE "prowlarr-main" OWNER TO prowlarr;
          ALTER DATABASE "prowlarr-logs" OWNER TO prowlarr;
        '';

        # WAL archive
        settings = {
          archive_mode = "on";
          archive_command = "${pkgs.barman}/bin/barman-cloud-wal-archive --cloud-provider aws-s3 --endpoint-url http://localhost:9000 s3://pg-backups pg-16 %p";
        };
      };

      age.secrets."s3.env".rekeyFile = commonSecret "s3.env";
      systemd.services.postgresql.serviceConfig.EnvironmentFile = config.age.secrets."s3.env".path;

      systemd.services.postgresql-base-backup = {
        description = "Full Base Backup de PostgreSQL vers MinIO";
        after = [
          "network.target"
          "postgresql.service"
        ];
        requires = [ "postgresql.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = "postgres";
          EnvironmentFile = config.age.secrets."s3.env".path;
        };
        script = ''
          ${pkgs.barman}/bin/barman-cloud-backup \
            --cloud-provider aws-s3 \
            --endpoint-url http://localhost:9000 \
            s3://pg-backups \
            pg-16 # server-name
        '';
        startAt = "03:00"; # Tous les jours à 3h
      };
    };

}
