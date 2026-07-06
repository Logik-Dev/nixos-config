{ ... }:
let
  servicesModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      # The generated job runs as the dedicated pgbackrest user, which cannot
      # read PGDATA: the existing cluster was initdb'd without
      # --allow-group-access (0700 postgres:postgres). Run it as postgres
      # instead, like barman today — on a single-admin host the isolation the
      # pgbackrest user buys is moot.
      systemd.services.pgbackrest-default-weekly = {
        after = [ "postgresql.service" ];
        requires = [ "postgresql.service" ];
        serviceConfig = {
          User = lib.mkForce "postgres";
          Group = lib.mkForce "postgres";
          EnvironmentFile = config.age.secrets."pgbackrest.env".path;
          # The module's ExecStart runs `backup` with no --repo, which only
          # backs up the FIRST repository — repo2 (Hetzner) would receive WAL
          # but never a base backup, i.e. no offsite PITR at all. Back up both
          # repos explicitly, sequentially.
          ExecStart = lib.mkForce [
            "${lib.getExe pkgs.pgbackrest} --stanza=default --repo=1 backup --type=full"
            "${lib.getExe pkgs.pgbackrest} --stanza=default --repo=2 backup --type=full"
          ];
        };
      };

      # Create the stanza at activation, not at the first Sunday backup:
      # the archive_command wrapper starts pushing WAL immediately after the
      # switch, and archive-push fails until the stanza exists (WAL would pile
      # up in pg_wal for days). Idempotent. Deliberately NOT a dependency of
      # postgresql.service — postgres must never wait on the USB disk or
      # Hetzner to start.
      systemd.services.pgbackrest-stanza-create = {
        description = "Create pgBackRest stanza (idempotent)";
        wantedBy = [ "multi-user.target" ];
        after = [
          "postgresql.service"
          "network-online.target"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "postgres";
          Group = "postgres";
          EnvironmentFile = config.age.secrets."pgbackrest.env".path;
          ExecStart = "${lib.getExe pkgs.pgbackrest} --stanza=default stanza-create";
        };
      };

      # archive-push runs INSIDE postgresql.service, which is sandboxed with
      # ProtectSystem=strict — everything is read-only except PGDATA. Without
      # these, the async spool/log writes and the repo1 (USB) archive writes
      # fail with [082] and ALL WAL archiving stalls (barman included, since
      # the wrapper fails as a whole). repo2 (sftp) needs no path: network only.
      systemd.services.postgresql.serviceConfig.ReadWritePaths = [
        "/var/spool/pgbackrest"
        "/var/log/pgbackrest"
        "/mnt/usb/pgbackrest"
        "/run/pgbackrest"
      ];
    };
in
{
  flake.modules.nixos.pgbackrest.imports = [ servicesModule ];
}
