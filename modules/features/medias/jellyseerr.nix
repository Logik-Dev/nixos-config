{ ... }:
{
  flake.modules.nixos.jellyseerr = {
    traefik.services.jellyseerr.port = 5055;

    services.seerr.enable = true;

    notify.services = [ "jellyseerr" ];

    backups.sources.jellyseerr = {
      paths = [ "/var/lib/jellyseerr" ];
      extraRepositories.local = "/mnt/local";
    };

  };
}
