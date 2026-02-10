{ ... }:
{
  flake.modules.nixos.hyper =
    { config, ... }:
    {
      services.flaresolverr.enable = true;
      services.mytraefik.services.jackett.port = 9117;

      services.jackett = {
        enable = true;
        dataDir = "/mnt/ultra/jackett";
      };

      services.backups.sources.jackett = {
        paths = [ config.services.jackett.dataDir ];
        extraRepositories.local = "/mnt/local";
      };

    };
}
