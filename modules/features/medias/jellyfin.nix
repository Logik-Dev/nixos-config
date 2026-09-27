{
  flake.modules.nixos.jellyfin =
    {
      config,
      pkgs,
      ...
    }:
    {
      imports = [ (import ./lib/_media-service.nix { app = "jellyfin"; }) ];

      traefik.services.jellyfin = {
        port = 8096;
        category = "Médias";
        icon = "di:jellyfin";
        # No Authelia on purpose: Jellyfin native clients (apps, TVs) need
        # direct access; the service has its own user system.
      };
      users.users.jellyfin.extraGroups = [
        "video"
        "render"
      ];

      services.jellyfin = {
        enable = true;
        dataDir = "/mnt/ultra/jellyfin";
      };

      hardware.graphics = {
        extraPackages = with pkgs; [
          libva-vdpau-driver
          nvidia-vaapi-driver
        ];
      };

      systemd.services.jellyfin = {
        environment = {
          LD_LIBRARY_PATH = "/run/opengl-driver/lib";
        };
      };

      notify.services = [ "jellyfin" ];

      backups.sources.jellyfin = {
        paths = [ config.services.jellyfin.dataDir ];
        # Logs and regenerable cache/transcode data — not worth shipping.
        exclude = [
          "${config.services.jellyfin.dataDir}/log"
          "${config.services.jellyfin.dataDir}/cache"
          "${config.services.jellyfin.dataDir}/transcodes"
        ];
      };
    };
}
