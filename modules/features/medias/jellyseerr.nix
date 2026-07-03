{ ... }:
{
  flake.modules.nixos.seerr = {
    traefik.services.seerr.port = 5055;
    traefik.services.seerr.enableAuthelia = true;

    services.seerr.enable = true;

    notify.services = [ "seerr" ];

    backups.sources.seerr = {
      paths = [ "/var/lib/jellyseerr" ];
      extraRepositories.local = "/mnt/local";
    };

  };
}
