_: {
  flake.modules.nixos.sonarr =
    {
      config,
      pkgs,
      ...
    }:
    {
      imports = [
        (import ./lib/_servarr.nix { inherit pkgs; } {
          app = "sonarr";
          mainDb = "sonarr-main";
          logDb = "sonarr-logs";
        })
        (import ./lib/_media-service.nix { app = "sonarr"; })
      ];

      traefik.services.sonarr = {
        port = 8989;
        enableAuthelia = true;
        category = "Médias";
        icon = "di:sonarr";
      };

      notify.services = [ "sonarr" ];

      services.sonarr = {
        enable = true;
        dataDir = "/mnt/ultra/sonarr";
      };

      backups.sources.sonarr = {
        paths = [ config.services.sonarr.dataDir ];
        # Same rationale as radarr: MediaCover is a regenerable artwork cache
        # and logs churn daily. Only the database is worth shipping.
        exclude = [
          "${config.services.sonarr.dataDir}/MediaCover"
          "${config.services.sonarr.dataDir}/logs"
        ];
      };
    };
}
