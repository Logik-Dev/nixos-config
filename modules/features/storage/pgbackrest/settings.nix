_:
let
  settingsModule =
    {
      config,
      ...
    }:
    let
      sb = config.constants.hosts.hyper.storageBox;
    in
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
      services.pgbackrest = {
        enable = true;

        settings = {
          # Async WAL archiving: archive-push acks PostgreSQL as soon as the
          # segment is in the local spool (/var/spool/pgbackrest); a background
          # process then ships it to both repos with retries, so postgres never
          # blocks on the USB disk or a Hetzner outage. Consequence: while a
          # repo is unreachable the spool GROWS on the root LV — it is bounded
          # by archive-push-queue-max (below) and watched by the
          # PgbackrestSpoolGrowing alert, so a stuck archiver cannot fill the
          # root filesystem (which would take PostgreSQL down).
          archive-async = true;
          spool-path = "/var/spool/pgbackrest";
          compress-type = "zst";
          process-max = 4;

          # The default lock-path is /tmp/pgbackrest — but postgresql.service
          # has PrivateTmp, so a `pgbackrest stop` issued from a shell writes
          # its stop file in a /tmp the in-service archive-push NEVER sees
          # (learned 2026-07-04: the "stopped" archiver kept hammering the
          # banned Storage Box for hours). /run is shared across the sandbox
          # boundary, so stop/start actually reach every pgbackrest process.
          lock-path = "/run/pgbackrest";
        };

        commands.archive-push = {
          # Keep WAL pushes gentle on the Storage Box: it enforces a connection
          # limit per IP and temporarily BANS the home IP when exceeded
          # (learned the hard way on 2026-07-04 — a retry storm during initial
          # debugging got port 22/23 refused for the whole house). 4 parallel
          # pushers, each with its own sftp session plus built-in retries, is
          # storm fuel; one is plenty for a homelab's WAL rate. Full backups
          # keep process-max=4.
          process-max = 1;

          # Hard cap on the async spool. At 2 GiB pgBackRest acks and DROPS the
          # queued WAL (PITR is interrupted until the next full backup) — a
          # deliberate trade: better a broken archive than a full root fs that
          # takes PostgreSQL down. The 512 MiB spool alert should fire long
          # before this.
          archive-push-queue-max = "2GiB";
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
          ${sb.host} = {
            type = "sftp";
            path = "/home/pgbackrest";
            retention-full = 8;
            cipher-type = "aes-256-cbc";
            bundle = true;
            block = true;
            sftp-host-user = sb.user;
            sftp-host-port = 23;
            sftp-private-key-file = config.age.secrets."hetzner-storagebox-pg".path;
            sftp-host-key-check-type = "strict";
            sftp-host-key-hash-type = "sha256";
            sftp-known-host = "/etc/ssh/ssh_known_hosts";
          };
        };

        # Weekly full at 03:30 Sunday, well before the 10:00 restic-verify
        # drill. The nixpkgs module turns this into pgbackrest-default-weekly
        # {.service,.timer}; the "default" stanza is auto-wired to the local
        # postgres instance.
        stanzas.default.jobs.weekly = {
          schedule = "Sun 03:30";
          type = "full";
        };
      };
    };
in
{
  flake.modules.nixos.pgbackrest.imports = [ settingsModule ];
}
