_: {
  flake.modules.nixos.navidrome = _: {
    services.navidrome = {
      enable = true;
      settings = {
        Address = "127.0.0.1"; # Traefik devant
        Port = 4533;
        MusicFolder = "/mnt/storage/medias/musique";
        # Le défaut `never` laisse des fantômes en base après suppression de
        # fichiers (ex. l'album de test WP5) ; `full` ne purge qu'après un scan
        # complet explicite, jamais sur un scan rapide — sans risque pour un
        # /mnt/storage monté `nofail` (le service ne démarre pas sans le bind).
        Scanner.PurgeMissing = "full";
        # Lidarr écrit `ARTISTS=Orelsan, FIFTY FIFTY` en **une seule valeur**
        # (crédit MusicBrainz combiné) ; le split par défaut ne s'applique
        # qu'aux ARTIST/ALBUMARTIST mono-valués (resources/mappings.yaml), donc
        # Navidrome créait un artiste « Orelsan, FIFTY FIFTY » au lieu de deux.
        Tags.Artists.Split = [ ", " ];
      };
      # Groupe primaire "media" (créé par le module seedbox) pour lire la
      # bibliothèque écrite par Lidarr/beets en UMask 0002.
      group = "media";
    };

    traefik.services.navidrome = {
      port = 4533;
      # PAS d'Authelia : clients Subsonic natifs + provider Music Assistant,
      # même raison que Jellyfin. Navidrome a son propre système de comptes.
      category = "Médias";
      icon = "di:navidrome";
    };

    notify.services = [ "navidrome" ];

    backups.sources.navidrome = {
      paths = [ "/var/lib/navidrome" ];
      # La DB (comptes, favoris, playlists) est la seule chose non
      # régénérable du service ; le cache (pochettes, transcodes) se refait
      # au scan. manageService par défaut : la DB est en SQLite, le service
      # est arrêté le temps du snapshot.
      exclude = [ "/var/lib/navidrome/cache" ];
    };
  };
}
