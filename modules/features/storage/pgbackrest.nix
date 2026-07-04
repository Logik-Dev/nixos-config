{ ... }:
{
  # pgBackRest — postgres PITR to two repos: repo1 = USB (posix), repo2 =
  # Hetzner Storage Box (sftp) → offsite PITR, which barman-cloud never had.
  # This replaces the barman-cloud → rustfs chain; during the transition the
  # archive_command in postgresql.nix pushes every WAL to BOTH chains (see the
  # wrapper there), and barman's weekly base backup keeps running until the
  # pgBackRest restore drill has been validated.
  #
  # Repo numbering is derived from the sorted attr names in `repos`:
  # "localhost" → repo1, "u625917.…" → repo2. Both repos are encrypted
  # (aes-256-cbc); the passphrase is NOT in this file — the nixpkgs module
  # forbids cipher-pass (it would land in the store), so it is injected as
  # PGBACKREST_REPO{1,2}_CIPHER_PASS via the agenix pgbackrest.env
  # EnvironmentFile on every unit that touches the repos (and on
  # postgresql.service for archive-push). Keep a copy of that passphrase in
  # Vaultwarden: without it the backups are unreadable.
  #
  # pgBackRest talks sftp through libssh2, NOT the ssh client — the
  # programs.ssh config from hetzner-storagebox.nix does not apply. Hence the
  # explicit repo-sftp-* options; host key pinning reuses
  # /etc/ssh/ssh_known_hosts, where programs.ssh.knownHosts already pins the
  # box's ed25519 key under [u625917.your-storagebox.de]:23.
  flake.modules.nixos.pgbackrest =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      services.pgbackrest = {
        enable = true;

        settings = {
          # Async WAL archiving: archive-push acks fast from a spool and a
          # background process ships to both repos with retries, so postgres
          # never blocks on the USB disk or a Hetzner outage. WAL is only
          # acknowledged once safely in ALL repos; if one is down, postgres
          # retains WAL in pg_wal and retries (disk-usage alerts cover runaway
          # growth).
          archive-async = true;
          spool-path = "/var/spool/pgbackrest";
          compress-type = "zst";
          process-max = 4;
        };

        repos = {
          # repo1 — USB disk. The name "localhost" is magic in the nixpkgs
          # module: any other name would be treated as a remote repo-host.
          localhost = {
            path = "/mnt/usb/pgbackrest";
            retention-full = 8;
            cipher-type = "aes-256-cbc";
            bundle = true;
            block = true;
          };

          # repo2 — Hetzner Storage Box, same box/key as the restic offsite.
          "u625917.your-storagebox.de" = {
            type = "sftp";
            path = "/home/pgbackrest";
            retention-full = 8;
            cipher-type = "aes-256-cbc";
            bundle = true;
            block = true;
            sftp-host-user = "u625917";
            sftp-host-port = 23;
            sftp-private-key-file = config.age.secrets."hetzner-storagebox".path;
            sftp-host-key-check-type = "strict";
            sftp-host-key-hash-type = "sha256";
            sftp-known-host = "/etc/ssh/ssh_known_hosts";
          };
        };

        # Weekly full at 03:30 Sunday (barman runs at 03:00 during the
        # double-run; both are gone quiet by the 05:00 restic-check). The
        # nixpkgs module turns this into pgbackrest-default-weekly
        # {.service,.timer}; the "default" stanza is auto-wired to the local
        # postgres instance.
        stanzas.default.jobs.weekly = {
          schedule = "Sun 03:30";
          type = "full";
        };
      };

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

      # libssh2 reads the sftp private key directly as the running user
      # (postgres), unlike restic where root reads it. Group-readable for
      # postgres; root (restic) is unaffected.
      age.secrets."hetzner-storagebox" = {
        group = "postgres";
        mode = "0440";
      };

      # The nixpkgs module points the pgbackrest user's home at
      # repos.localhost.path and would chown the USB repo dir at activation;
      # detach it — the repo dir belongs to postgres (see tmpfiles below).
      users.users.pgbackrest.home = lib.mkForce "/var/lib/pgbackrest";

      systemd.tmpfiles.rules = [
        "d /mnt/usb/pgbackrest 0750 postgres postgres -"
        "d /var/spool/pgbackrest 0750 postgres postgres -"
        # restore lock dir, used by the (future) pgbackrest restore drill; the
        # nixpkgs module sets commands.restore.lock-path here but never
        # creates it.
        "d /tmp/postgresql 0750 postgres postgres -"
      ];

      notify.services = [
        "pgbackrest-default-weekly"
        "pgbackrest-stanza-create"
      ];
    };
}
