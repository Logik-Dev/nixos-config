{ homelab, lib, ... }:

{

  sops.secrets."torrent.env" = {
    sopsFile = ./torrent.env;
    format = "dotenv";
    key = "";
    restartUnits = [ "podman-qbittorrent.service" ];
  };

  # Container
  virtualisation.oci-containers.containers."qbittorrent" = {
    image = "lscr.io/linuxserver/qbittorrent:latest";
    log-driver = "journald";
    environmentFiles = [
      "/run/secrets/torrent.env"
    ];
    volumes = [
      "/medias/downloads:/medias/downloads:rw"
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
    after = [
      "podman-network-seedbox_default.service"
    ];
    requires = [
      "podman-network-seedbox_default.service"
    ];
    partOf = [
      "podman-compose-seedbox-root.target"
    ];
    wantedBy = [
      "podman-compose-seedbox-root.target"
    ];
  };

  # Nginx
  services.nginx.virtualHosts."torrent.${homelab.domain}" = {
    enableACME = true;
    forceSSL = true;
    acmeRoot = null;
    locations."/" = {
      proxyPass = "http://localhost:8080";
    };
  };

  users.groups.media.gid = 991;

  # Containers's config directories
  systemd.tmpfiles.settings = {
    "10-containers-config-dir" = {
      "/var/lib/containers" = {
        d = {
          group = "media";
          mode = "775";
          user = homelab.username;
        };
      };
      "/medias/downloads/movies" = {
        d = {
          group = "media";
          mode = "775";
          user = homelab.username;
        };
      };
      "/medias/downloads/series" = {
        d = {
          group = "media";
          mode = "775";
          user = homelab.username;
        };
      };
    };
  };

}
