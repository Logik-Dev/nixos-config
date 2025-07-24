{ pkgs, ... }:
{
  users.groups.media = { };

  # jellyfin
  services.jellyfin.enable = true;
  services.jellyfin.group = "media";
  services.traefik-proxy.services.jellyfin.port = 8096;

  # audiobookshelf
  services.audiobookshelf.enable = true;
  services.audiobookshelf.group = "media";
  services.audiobookshelf.host = "0.0.0.0";
  services.traefik-proxy.services.books.port = 8000;

  # prowlarr
  services.prowlarr.enable = true;
  services.traefik-proxy.services.prowlarr.port = 9696;

  # radarr
  services.radarr.enable = true;
  services.radarr.group = "media";
  services.traefik-proxy.services.radarr.port = 7878;

  # sonarr
  services.sonarr.enable = true;
  services.sonarr.group = "media";
  services.traefik-proxy.services.sonarr.port = 8989;

  # jellyseerr
  services.jellyseerr.enable = true;
  services.traefik-proxy.services.jellyseerr.port = 5055;

  # enable vaapi on OS-level
  nixpkgs.config.packageOverrides = pkgs: {
    vaapiIntel = pkgs.vaapiIntel.override { enableHybridCodec = true; };
  };

  # graphics
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
