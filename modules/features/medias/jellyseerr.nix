{ ... }:
{
  flake.modules.nixos.jellyseerr = {
    traefik.services.jellyseerr.port = 5055;

    services.jellyseerr.enable = true;

    backups.sources.jellyseerr = {
      paths = [ "/var/lib/jellyseerr" ];
      extraRepositories.local = "/mnt/local";
    };

  };
}
