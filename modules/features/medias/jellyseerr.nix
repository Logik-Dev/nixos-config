{ ... }:
{
  flake.modules.nixos.seerr = {
    traefik.services.seerr.port = 5055;

    services.seerr.enable = true;

    notify.services = [ "seerr" ];

    backups.sources.seerr = {
      paths = [ "/var/lib/jellyseerr" ];
      extraRepositories.local = "/mnt/local";
    };

  };
}
