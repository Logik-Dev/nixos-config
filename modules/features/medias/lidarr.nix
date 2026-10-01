_: {
  flake.modules.nixos.lidarr =
    {
      config,
      pkgs,
      ...
    }:
    {
      imports = [
        (import ./lib/_servarr.nix { inherit pkgs; } {
          app = "lidarr";
          mainDb = "lidarr-main";
          logDb = "lidarr-logs";
        })
        (import ./lib/_media-service.nix { app = "lidarr"; })
      ];

      traefik.services.lidarr = {
        port = 8686;
        enableAuthelia = true;
        category = "Médias";
        icon = "di:lidarr";
      };

      services.lidarr = {
        enable = true;
        dataDir = "/mnt/ultra/lidarr";
      };

      # /mnt/ultra est monté `nofail` : sans dépendance de montage, un démarrage
      # avant le disque écrirait la base dans le disque racine (cf.
      # docs/services.md, « Contraintes /mnt/ultra »). radarr/sonarr/jellyfin
      # n'ont pas encore cette garde — à généraliser dans lib/_media-service.nix
      # plutôt qu'à recopier.
      systemd.services.lidarr.unitConfig.RequiresMountsFor = [ "/mnt/ultra" ];

      notify.services = [ "lidarr" ];

      backups.sources.lidarr = {
        paths = [ config.services.lidarr.dataDir ];
        # MediaCover (pochettes récupérées à la demande) et logs : pur cache
        # qui churn quotidiennement. Ce qui compte ici, c'est config.xml (clé
        # API, réglages) ; les bases sont dans Postgres (pgBackRest).
        exclude = [
          "${config.services.lidarr.dataDir}/MediaCover"
          "${config.services.lidarr.dataDir}/logs"
        ];
      };
    };
}
