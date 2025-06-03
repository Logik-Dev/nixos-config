{ username, lib, ... }:

{

  sops.secrets."torrent.env" = {
    sopsFile = ../../secrets/torrent.docker.env;
    format = "dotenv";
    key = "";
    restartUnits = [ "podman-qbittorrent.service" ];
  };

  # qbittorrent port
  networking.firewall.allowedTCPPorts = [ 8080 ];

  # Container
  virtualisation.oci-containers.containers."qbittorrent" = {
    image = "lscr.io/linuxserver/qbittorrent:latest";
    log-driver = "journald";
    environmentFiles = [
      "/run/secrets/torrent.env"
    ];
    volumes = [
      "/medias/downloads:/medias/downloads:rw"
      "/medias/ratio:/medias/ratio:rw"
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

  users.groups.media.gid = 991;

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
      "/medias/downloads/movies" = {
        d = {
          group = "media";
          mode = "770";
          user = username;
        };
      };
      "/medias/downloads/series" = {
        d = {
          group = "media";
          mode = "770";
          user = username;
        };
      };
      "/medias/ratio" = {
        d = {
          group = "media";
          mode = "770";
          user = username;
        };
      };
    };
  };

}
