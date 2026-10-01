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
          ALTER DATABASE "lidarr-main" OWNER TO lidarr;
          ALTER DATABASE "lidarr-logs" OWNER TO lidarr;
          SQL
        '')
      ];

      systemd.tmpfiles.rules = [
        "d /mnt/storage/medias 2755 logikdev media - -"
        # Bindery imports here; setgid so new files inherit the media group.
        "d /mnt/storage/medias/books 2775 logikdev media - -"
        "d /mnt/storage/medias/audiobooks 2775 logikdev media - -"
        # Racine musique : Lidarr écrit populaire/, beets classique/ ; setgid
        # pour que les imports héritent du groupe media.
        "d /mnt/storage/medias/musique 2775 logikdev media - -"
        # Racine Lidarr (doit exister avant d'être déclarée dans l'UI) et
        # dossier de téléchargement commun SABnzbd/qBittorrent (catégorie
        # `lidarr`, même motif que movies/series).
        "d /mnt/storage/medias/musique/populaire 2775 logikdev media - -"
        "d /mnt/storage/medias/downloads/lidarr 2775 logikdev media - -"
        "d /mnt/ultra 2755 logikdev media - -"
      ];

      imports = with inputs.self.modules.nixos; [
        audiobookshelf
        beets
        bindery
        jellyfin
        jellyseerr
        lidarr
        lidarr-metadata
        musique-import
        navidrome
        prowlarr
        radarr
        sabnzbd
        sonarr
      ];
    };
}
