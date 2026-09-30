_: {
  flake.modules.nixos.navidrome = _: {
    services.navidrome = {
      enable = true;
      settings = {
        Address = "127.0.0.1"; # Traefik devant
        Port = 4533;
        MusicFolder = "/mnt/storage/medias/musique";
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
