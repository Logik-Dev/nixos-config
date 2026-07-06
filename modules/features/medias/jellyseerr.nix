{ ... }:
{
  flake.modules.nixos.seerr = {
    traefik.services.seerr = {
      port = 5055;
      enableAuthelia = true;
      category = "Médias";
      icon = "di:jellyseerr";
      title = "Jellyseerr";
    };

    services.seerr.enable = true;

    notify.services = [ "seerr" ];

    backups.sources.seerr = {
      paths = [ "/var/lib/jellyseerr" ];
      extraRepositories.local = "/mnt/local";
    };

  };
}
