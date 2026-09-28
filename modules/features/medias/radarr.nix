_: {
  flake.modules.nixos.radarr =
    {
      config,
      pkgs,
      ...
    }:
    {
      imports = [
        (import ./lib/_servarr.nix { inherit pkgs; } {
          app = "radarr";
          mainDb = "radarr-main";
          logDb = "radarr-logs";
        })
        (import ./lib/_media-service.nix { app = "radarr"; })
      ];

      traefik.services.radarr = {
        port = 7878;
        enableAuthelia = true;
        category = "Médias";
        icon = "di:radarr";
      };

      services.radarr = {
        enable = true;
        dataDir = "/mnt/ultra/radarr";
      };

      notify.services = [ "radarr" ];

      backups.sources.radarr = {
        paths = [ config.services.radarr.dataDir ];
        # MediaCover (1.3 GB) is a poster/fanart cache Radarr re-fetches on
        # demand, and it churns daily — so every snapshot stored new chunks,
        # which is why the repo had grown to 3.9 GB for 1.4 GB of state. The
        # database (~10 MB) is the only part a restore actually needs.
        exclude = [
          "${config.services.radarr.dataDir}/MediaCover"
          "${config.services.radarr.dataDir}/logs"
        ];
      };
    };
}
