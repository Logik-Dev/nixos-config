{ ... }:
{

  services.backups.enable = true;
  services.backups.configurations = {
    photos = {
      source_directories = [ "/mnt/photos/immich" ];
      services = [
        "immich-server"
        "immich-machine-learning"
      ];
    };
    medias-apps = {
      source_directories = [
        "/var/lib/jellyfin"
        "/var/lib/radarr"
        "/var/lib/sonarr"
        "/var/lib/private/prowlarr"
        "/var/lib/private/jellyseerr"
      ];
      services = [
        "jellyfin"
        "radarr"
        "sonarr"
        "prowlarr"
        "jellyseerr"
      ];
    };
  };
}
