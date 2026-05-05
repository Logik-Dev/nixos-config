{ ... }:
{

  flake.modules.nixos.postgresql =
    {
      pkgs,
      config,
      ...
    }:
    {
      services.postgresql = {
        enable = true;

        # WAL archive
        settings = {
          archive_mode = "on";
          archive_command = "${pkgs.barman}/bin/barman-cloud-wal-archive --cloud-provider aws-s3 --endpoint-url http://localhost:9000 s3://pg-backups pg-16 %p";
        };
      };

      notify.services = [ "postgresql" ];

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
          set -euo pipefail

          SERVER=pg-16
          S3_BUCKET=s3://pg-backups
          ENDPOINT=http://localhost:9000
          PROVIDER=aws-s3
          RETENTION=8

          echo "==> Base backup..."
          ${pkgs.barman}/bin/barman-cloud-backup \
            --cloud-provider "$PROVIDER" \
            --endpoint-url "$ENDPOINT" \
            "$S3_BUCKET" \
            "$SERVER"

          echo "==> Suppression des anciens base backups (rétention: $RETENTION)..."
          ${pkgs.barman}/bin/barman-cloud-backup-delete \
            --cloud-provider "$PROVIDER" \
            --endpoint-url "$ENDPOINT" \
            --retention-policy "REDUNDANCY $RETENTION" \
            "$S3_BUCKET" \
            "$SERVER"

          echo "==> Backup terminé."
        '';

        startAt = "Sun 03:00";
      };
    };

}
