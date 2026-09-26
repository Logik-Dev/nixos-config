{ inputs, ... }:
{
  flake.modules.nixos.seedbox =
    { config, pkgs, ... }:
    {

      users.groups.media.gid = config.constants.media.gid;

      # ensureUsers only creates the roles and ensureDatabases the DBs; the
      # <app>-main/-logs names don't match the roles, so ensureDBOwnership
      # cannot be used and ownership stays with postgres. The old
      # services.postgresql.initialScript could never fix that (it ran before
      # the databases existed, without ON_ERROR_STOP, and only on first init).
      # Transfer ownership idempotently after the setup script on every boot
      # instead — PG15+ requires the app role to own the database to create
      # tables in schema public.
      systemd.services.postgresql-setup.serviceConfig.ExecStartPost = [
        (pkgs.writeShellScript "seedbox-db-ownership" ''
          set -euo pipefail
          ${config.services.postgresql.finalPackage}/bin/psql -d postgres -v ON_ERROR_STOP=1 <<'SQL'
          ALTER DATABASE "sonarr-main" OWNER TO sonarr;
          ALTER DATABASE "sonarr-logs" OWNER TO sonarr;
          ALTER DATABASE "radarr-main" OWNER TO radarr;
          ALTER DATABASE "radarr-logs" OWNER TO radarr;
          ALTER DATABASE "prowlarr-main" OWNER TO prowlarr;
          ALTER DATABASE "prowlarr-logs" OWNER TO prowlarr;
          SQL
        '')
      ];

      systemd.tmpfiles.rules = [
        "d /mnt/storage/medias 2755 logikdev media - -"
        "d /mnt/ultra 2755 logikdev media - -"
      ];

      imports = with inputs.self.modules.nixos; [
        jellyfin
        jellyseerr
        prowlarr
        radarr
        sabnzbd
        sonarr
      ];
    };
}
