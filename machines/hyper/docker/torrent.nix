{ username, lib, ... }:

{

  sops.secrets."torrent.env" = {
    sopsFile = ../../../secrets/torrent.hyper.env;
    format = "dotenv";
    key = "";
    restartUnits = [ "podman-qbittorrent.service" ];
  };

  # qbittorrent port
  services.traefik-proxy.services.torrent.port = 8080;

  # Container
  virtualisation.oci-containers.containers."qbittorrent" = {
    image = "lscr.io/linuxserver/qbittorrent:latest";
    log-driver = "journald";
    environmentFiles = [
      "/run/secrets/torrent.env"
    ];
    volumes = [
      "/mnt/storage/medias/downloads:/mnt/storage/medias/downloads:rw"
      "/mnt/storage/medias/ratio:/mnt/storage/medias/ratio:rw"
      "/var/lib/containers:/config:rw"
    ];
    dependsOn = [
      "seedbox-gluetun"
    ];
    extraOptions = [
      "--network=container:seedbox-gluetun"
    ];
  };

  # Service
  systemd.services."podman-qbittorrent" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    partOf = [
      "podman-compose-seedbox-root.target"
    ];
    wantedBy = [
      "podman-compose-seedbox-root.target"
    ];
  };

  # Containers's config directories
  systemd.tmpfiles.settings = {
    "10-containers-config-dir" = {
      "/var/lib/containers" = {
        d = {
          group = "media";
          mode = "770";
          user = username;
        };
      };
    };
  };

}
