{ ... }:
{

  flake.modules.nixos.postgresql =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      sb = config.constants.hosts.hyper.storageBox;
    in
    {
      # WAL archiving (archive_mode + archive_command → pgbackrest archive-push)
      # is set by the pgbackrest nixpkgs module itself; the whole PITR chain
      # lives in storage/pgbackrest.nix (repo1 usb + repo2 Hetzner offsite).
      # barman-cloud → rustfs was decommissioned 2026-07-04; its store stays
      # frozen at /mnt/ultra/rustfs/pg-backups until J+14 as a safety net.
      services.postgresql.enable = true;

      notify.services = [
        "postgresql"
        "pg-dumpall"
      ];

      # pgbackrest.env = repo cipher passphrases, needed by archive-push which
      # runs inside postgresql.service.
      systemd.services.postgresql.serviceConfig.EnvironmentFile = [
        config.age.secrets."pgbackrest.env".path
      ];

      systemd.tmpfiles.rules = [ "d /mnt/ultra/pg-dump 0700 postgres postgres -" ];

      # OFFSITE logical backup of the whole cluster (roles + every DB).
      # pgBackRest is the PITR primary, but a plain pg_dumpall remains the
      # disaster path of last resort: tiny, restorable with psql alone (no
      # pgBackRest, no cipher passphrase, no repo layout knowledge needed),
      # shipped to Hetzner + usb. The crown jewels (vaultwarden vault,
      # prowlarr, immich metadata) all live in postgres — belt and suspenders.
      # The dump runs ONCE per day (01:30) into a fixed filename, so both
      # restic targets (which start at 02:05+ and used to each re-dump via
      # runBefore) ship the exact same, fresh dump. RequiresMountsFor keeps it
      # off the root filesystem if /mnt/ultra is missing.
      systemd.services.pg-dumpall = {
        description = "Daily logical dump of the whole PostgreSQL cluster";
        startAt = "*-*-* 01:30:00";
        unitConfig.RequiresMountsFor = [ "/mnt/ultra" ];
        serviceConfig = {
          Type = "oneshot";
          User = "postgres";
          Group = "postgres";
        };
        script = ''
          set -euo pipefail
          out=/mnt/ultra/pg-dump
          ${config.services.postgresql.finalPackage}/bin/pg_dumpall --clean --if-exists \
            > "$out/pg-dumpall.sql.tmp"
          mv -f "$out/pg-dumpall.sql.tmp" "$out/pg-dumpall.sql"
        '';
      };

      backups.sources.pg-dump = {
        paths = [ "/mnt/ultra/pg-dump" ];
        manageService = false;
        defaultRepositories = {
          hetzner = "sftp:${sb.user}@${sb.host}:/home";
          usb = "/mnt/usb";
        };
      };

    };

}
