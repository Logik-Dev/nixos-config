_:
let
  secretsModule =
    {
      config,
      lib,
      ...
    }:
    {
      # pgbackrest (libssh2, runs as postgres) gets its OWN decrypted copy of
      # the Storage Box key, from the same .age file. Hard-earned lesson
      # (2026-07-04/05, two days of Hetzner fail2ban bans): this one key file
      # has THREE kinds of readers with incompatible constraints —
      #   1. restic backup units & drills: full root, read anything;
      #   2. restic exporters: uid 0 but CapabilityBoundingSet="" strips
      #      CAP_DAC_OVERRIDE, so they can ONLY read root-owned perm bits;
      #   3. pgbackrest: plain postgres user.
      # Any single file satisfying 2 and 3 needs group perms — and OpenSSH
      # refuses a group-readable key when the caller owns it ("UNPROTECTED
      # PRIVATE KEY FILE"), which silently turned every restic connection into
      # failed logins that fed Hetzner's fail2ban. Two tight copies, zero
      # cleverness: the base secret stays root:0400 for all ssh clients, this
      # one is postgres:0400 for libssh2.
      age.secrets."hetzner-storagebox-pg" = {
        rekeyFile = config.age.secrets."hetzner-storagebox".rekeyFile;
        owner = "postgres";
        mode = "0400";
      };

      # The nixpkgs module points the pgbackrest user's home at
      # repos.localhost.path and would chown the USB repo dir at activation;
      # detach it — the repo dir belongs to postgres (see tmpfiles below).
      users.users.pgbackrest.home = lib.mkForce "/var/lib/pgbackrest";

      systemd.tmpfiles.rules = [
        "d /mnt/usb/pgbackrest 0750 postgres postgres -"
        "d /var/spool/pgbackrest 0750 postgres postgres -"
        "d /run/pgbackrest 0750 postgres postgres -"
        # The async archive-push process unconditionally writes its own log
        # under log-path (default /var/log/pgbackrest) even with
        # log-level-file=off, and aborts with [082] if the dir is missing —
        # which blocks ALL WAL archiving (barman included, via the wrapper).
        "d /var/log/pgbackrest 0750 postgres postgres -"
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
in
{
  flake.modules.nixos.pgbackrest.imports = [ secretsModule ];
}
