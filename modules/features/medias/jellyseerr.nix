{ ... }:
{
  flake.modules.nixos.hyper = {
    services = {
      jellyseerr.enable = true;
      mytraefik.services.jellyseerr.port = 5055;
      backups.sources.jellyseerr = {
        paths = [ "/var/lib/jellyseerr" ];
        extraRepositories.local = "/mnt/local";
      };
    };

  };
}
