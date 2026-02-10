{
  flake.modules.nixos.seedbox =
    {
      pkgs,
      config,
      ...
    }:
    {
      services.mytraefik.services.jellyfin.port = 8096;
      users.users.jellyfin.extraGroups = [
        "video"
        "render"
      ];

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

      services.backups.sources.jellyfin = {
        paths = [ config.services.jellyfin.dataDir ];
        extraRepositories.local = "/mnt/local";
      };
    };
}
