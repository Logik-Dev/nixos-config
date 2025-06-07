{
  lib,
  pkgs,
  username,
  ...
}:
{

  imports = [
    ./backups.nix
    ./immich.nix
    ./jellyfin.nix
  ];

  networking.networkmanager.enable = lib.mkForce false;

  users.groups.media = { };

  # medias folders
  systemd.tmpfiles.settings = {
    "10-medias-folders" = {
      "/medias" = {
        d = {
          group = "media";
          mode = "750";
          user = username;
        };
      };
    };
  };

  # prowlarr
  services.prowlarr.enable = true;
  services.prowlarr.openFirewall = true;

  # radarr
  services.radarr.enable = true;
  services.radarr.openFirewall = true;
  services.radarr.group = "media";

  # sonarr
  services.sonarr.enable = true;
  services.sonarr.openFirewall = true;
  services.sonarr.group = "media";

  # jellyseerr
  services.jellyseerr.enable = true;
  services.jellyseerr.openFirewall = true;

  # 1. enable vaapi on OS-level
  nixpkgs.config.packageOverrides = pkgs: {
    vaapiIntel = pkgs.vaapiIntel.override { enableHybridCodec = true; };
  };
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-vaapi-driver
      vaapiVdpau
      intel-compute-runtime # OpenCL filter support (hardware tonemapping and subtitle burn-in)
      intel-media-sdk # QSV up to 11th gen
    ];
  };
}
