{ pkgs, ... }:
{

  environment.systemPackages = [
    pkgs.jellyfin
    pkgs.jellyfin-web
    pkgs.jellyfin-ffmpeg
  ];

  # jellyfin
  services.jellyfin.enable = true;
  services.jellyfin.group = "media";
  services.jellyfin.openFirewall = true;

}
