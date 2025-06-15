{ lib, ... }:
{

  sops.secrets."gluetun.env" = {
    sopsFile = ../../secrets/gluetun.docker.env;
    format = "dotenv";
    key = "";
    restartUnits = [ "podman-seedbox-gluetun.service" ];
  };

  virtualisation.oci-containers.containers."seedbox-gluetun" = {
    image = "qmcgaw/gluetun";
    log-driver = "journald";
    environmentFiles = [
      "/run/secrets/gluetun.env"
    ];
    extraOptions = [
      "--cap-add=NET_ADMIN"
      "--device=/dev/net/tun:/dev/net/tun:rwm"
      "--network-alias=gluetun"
      "--network=seedbox_default"
    ];
    ports = [
      "8080:8080/tcp"
      "47594/tcp"
      "47594/udp"
    ];

  };
  systemd.services."podman-seedbox-gluetun" = {
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

}
