{ ... }:
{
  flake.modules.nixos.prowlarr =
    { config, pkgs, ... }:
    {
      imports = [
        (import ./lib/_servarr.nix { inherit pkgs; } {
          app = "prowlarr";
          mainDb = "prowlarr-main";
          logDb = "prowlarr-logs";
        })
      ];

      traefik.services.prowlarr = {
        port = 9696;
        enableAuthelia = true;
        category = "Médias";
        icon = "di:prowlarr";
      };

      services.prowlarr = {
        enable = true;
        dataDir = "/mnt/ultra/prowlarr";
      };

      notify.services = [ "prowlarr" ];

      # Indexer configs + API key (config.xml); the DB itself is in postgres.
      backups.sources.prowlarr = {
        paths = [ config.services.prowlarr.dataDir ];
        extraRepositories.local = "/mnt/local";
      };
    };
}
