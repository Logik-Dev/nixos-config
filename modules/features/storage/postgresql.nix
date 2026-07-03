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

      # OFFSITE logical backup of the whole cluster (roles + every DB).
      # barman above is the on-site PITR primary, but its store lives in rustfs
      # (on-site only), so postgres had no offsite copy — yet the crown jewels
      # (vaultwarden vault, prowlarr, immich metadata) all live here. This
      # pg_dumpall is small and trivially restorable (pg_restore/psql, no S3
      # needed) and is shipped to Hetzner + usb, closing the 3-2-1 gap.
      # The dump is written to a fixed filename (overwritten each run) so the
      # staging dir never accumulates; restic retention bounds the repo history.
      backups.sources.pg-dump = {
        paths = [ "/mnt/ultra/pg-dump" ];
        manageService = false;
        defaultRepositories = {
          hetzner = "sftp:u625917@u625917.your-storagebox.de:/home";
          usb = "/mnt/usb";
        };
        runBefore = "${pkgs.writeShellScript "pg-dumpall" ''
          set -euo pipefail
          mkdir -p /mnt/ultra/pg-dump
          ${pkgs.util-linux}/bin/runuser -u postgres -- \
            ${config.services.postgresql.finalPackage}/bin/pg_dumpall --clean --if-exists \
            > /mnt/ultra/pg-dump/pg-dumpall.sql.tmp
          mv -f /mnt/ultra/pg-dump/pg-dumpall.sql.tmp /mnt/ultra/pg-dump/pg-dumpall.sql
        ''}";
      };
    };

}
