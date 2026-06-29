{ ... }:
{
  flake.modules.nixos.seerr = {
    traefik.services.seerr.port = 5055;

    services.seerr.enable = true;

    notify.services = [ "seerr" ];

    backups.sources.seerr = {
      paths = [ "/var/lib/seerr" ];
      extraRepositories.local = "/mnt/local";
    };

  };
}
