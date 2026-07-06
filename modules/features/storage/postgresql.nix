{ ... }:
{

  flake.modules.nixos.postgresql =
    {
      pkgs,
      config,
      lib,
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

      notify.services = [ "postgresql" ];

      # pgbackrest.env = repo cipher passphrases, needed by archive-push which
      # runs inside postgresql.service.
      systemd.services.postgresql.serviceConfig.EnvironmentFile = [
        config.age.secrets."pgbackrest.env".path
      ];

      # OFFSITE logical backup of the whole cluster (roles + every DB).
      # pgBackRest is the PITR primary, but a plain pg_dumpall remains the
      # disaster path of last resort: tiny, restorable with psql alone (no
      # pgBackRest, no cipher passphrase, no repo layout knowledge needed),
      # shipped to Hetzner + usb. The crown jewels (vaultwarden vault,
      # prowlarr, immich metadata) all live in postgres — belt and suspenders.
      # The dump is written to a fixed filename (overwritten each run) so the
      # staging dir never accumulates; restic retention bounds the repo history.
      backups.sources.pg-dump = {
        paths = [ "/mnt/ultra/pg-dump" ];
        manageService = false;
        defaultRepositories = {
          hetzner = "sftp:${sb.user}@${sb.host}:/home";
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
