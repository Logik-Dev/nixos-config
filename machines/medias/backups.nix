{ ... }:
let
  immichServices = [
    "immich-server"
    "immich-machine-learning"
  ];
  paperlessServices = [
    "paperless-consumer"
    "paperless-scheduler"
    "paperless-web"
    "paperless-task-queue"
  ];
in

{

  services.backups.enable = true;
  services.backups.configurations = {

    # photos
    photos = {
      services = immichServices;
      source_directories = [ "/mnt/photos/immich" ];
    };

    # documents
    documents = {
      services = paperlessServices;
      source_directories = [ "/mnt/photos/documents" ];
    };

    # immich
    immich = {
      services = immichServices;
      postgresql_databases = [
        {
          name = "immich";
          username = "immich";
        }
      ];
    };

    # medias apps
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

    # paperless
    paperless = {
      services = paperlessServices;
      source_directories = [
        "/var/lib/paperless"
      ];
      postgresql_databases = [
        {
          name = "paperless";
          username = "paperless";
        }
      ];
    };
  };
}
