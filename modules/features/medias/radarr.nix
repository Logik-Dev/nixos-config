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
      };
    };
}
