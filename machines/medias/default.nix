{
  lib,
  pkgs,
  username,
  ...
}:
{

  imports = [
    ./borgmatic.nix
    ./jellyfin.nix
  ];

  networking.networkmanager.enable = lib.mkForce false;

  users.groups.media = { };

  # Medias folders
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

  networking.firewall.allowedTCPPorts = [
    9696
    7878
    8989
    8096
    5055
  ];

  services.prowlarr.enable = true;
  services.radarr.enable = true;
  services.radarr.group = "media";
  services.sonarr.enable = true;
  services.sonarr.group = "media";
  services.jellyseerr.enable = true;

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
