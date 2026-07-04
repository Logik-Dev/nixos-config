{ ... }:
{

  flake.modules.nixos.postgresql =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    {
      services.postgresql = {
        enable = true;

        # WAL archive — TRANSITION barman → pgBackRest (double-run).
        # Every WAL segment is pushed to BOTH chains; the command fails (and
        # postgres retains + retries the WAL) if EITHER push fails, so neither
        # chain can silently develop a gap while pgBackRest is being proven.
        # mkForce because the pgbackrest nixpkgs module also sets
        # archive_command when postgres is enabled. Once the pgBackRest restore
        # drill is validated: drop the barman line, keep archive-push only.
        settings = {
          archive_mode = "on";
          archive_command = lib.mkForce "${pkgs.writeShellScript "wal-archive-both" ''
            set -euo pipefail
            ${pkgs.barman}/bin/barman-cloud-wal-archive --cloud-provider aws-s3 --endpoint-url http://localhost:9000 s3://pg-backups pg-16 "$1"
            exec ${lib.getExe pkgs.pgbackrest} --stanza=default archive-push "$1"
          ''} %p";
        };
      };

      notify.services = [ "postgresql" ];

      # s3.env = barman creds (dropped with barman at the end of the
      # transition); pgbackrest.env = repo cipher passphrases for archive-push.
      systemd.services.postgresql.serviceConfig.EnvironmentFile = [
        config.age.secrets."s3.env".path
        config.age.secrets."pgbackrest.env".path
      ];

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

      # barman's PITR store (WAL archive + weekly base backup) lives only in the
      # rustfs blob store (s3://pg-backups, on disk at /mnt/ultra/rustfs/pg-backups,
      # ~24 GB). We used to get a USB copy for free inside the wholesale rustfs-usb
      # backup, but that dragged ~440 GB of duplicated immich along with it. Now
      # that rustfs-usb is gone, back up just the barman store to USB so its PITR
      # capability survives a loss of the rustfs disk. Raw files are read live (no
      # snapshot): barman objects are write-once WAL + weekly base tars, so torn
      # reads are unlikely and self-heal on the next run; the pg-dumpall offsite
      # copy remains the authoritative disaster path anyway.
      backups.sources.pg-barman = {
        paths = [ "/mnt/ultra/rustfs/pg-backups" ];
        manageService = false;
        defaultRepositories = {
          usb = "/mnt/usb";
        };
      };
    };

}
