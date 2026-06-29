{
  flake.modules.nixos.jellyfin =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      traefik.services.jellyfin.port = 8096;
      users.users.jellyfin.extraGroups = [
        "video"
        "render"
      ];

      systemd.services.jellyfin.serviceConfig.UMask = lib.mkForce "0002";

      services.jellyfin = {
        enable = true;
        group = "media";
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
        extraRepositories.local = "/mnt/local";
      };
    };
}
