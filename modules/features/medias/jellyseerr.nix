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
      # DynamicUser + StateDirectory: /var/lib/jellyseerr is a symlink to
      # /var/lib/private/jellyseerr, so backing up the former only saves the
      # link. stateRevision 0 -> data lives under /var/lib/private/jellyseerr.
      paths = [ "/var/lib/private/jellyseerr" ];
      extraRepositories.local = "/mnt/local";
    };

  };
}
