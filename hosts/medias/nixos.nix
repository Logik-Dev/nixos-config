{
  homelab,
  lib,
  pkgs,
  ...
}:
let
  domain = homelab.domain;

  mkProxy = port: {
    enableACME = true;
    forceSSL = true;
    acmeRoot = null;
    locations."/" = {
      proxyWebsockets = true;
      proxyPass = "http://localhost:${toString port}";
    };
  };

in
{

  imports = [
    ./borgmatic.nix
  ];

  networking.networkmanager.enable = lib.mkForce false;

  users.groups.media = { };
  #users.users.radarr.extraGroups = [ "media" ];
  #users.users.sonarr.extraGroups = [ "media" ];
  #users.users.jellyfin.extraGroups = [ "media" ];

  # Medias folders
  systemd.tmpfiles.settings = {
    "10-medias-folders" = {
      "/medias/movies" = {
        d = {
          group = "media";
          mode = "775";
          user = "radarr";
        };
      };
      "/medias/series" = {
        d = {
          group = "media";
          mode = "775";
          user = "sonarr";
        };
      };
    };
  };

  # Prowlarr
  services.prowlarr.enable = true;
  services.nginx.virtualHosts."prowlarr.${domain}" = mkProxy 9696;

  # Radarr
  services.radarr.enable = true;
  services.radarr.group = "media";
  services.nginx.virtualHosts."radarr.${domain}" = mkProxy 7878;

  # Sonarr
  services.sonarr.enable = true;
  services.sonarr.group = "media";
  services.nginx.virtualHosts."sonarr.${domain}" = mkProxy 8989;

  # Jellyfin
  services.jellyfin.enable = true;
  services.jellyfin.group = "media";
  services.nginx.virtualHosts."jellyfin.${domain}" = mkProxy 8096;

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
