{ ... }:
{
  flake.modules.nixos.jackett =
    { config, ... }:
    {
      services.flaresolverr.enable = true;
      traefik.services.jackett.port = 9117;

      services.jackett = {
        enable = true;
        dataDir = "/mnt/ultra/jackett";
      };

      backups.sources.jackett = {
        paths = [ config.services.jackett.dataDir ];
        extraRepositories.local = "/mnt/local";
      };

    };
}
