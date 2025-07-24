{ lib, ... }:
{

  services.traefik-proxy.services.flaresolverr.port = 8191;

  # Container
  virtualisation.oci-containers.containers."flaresolverr" = {
    image = "21hsmw/flaresolverr:nodriver";
    environment = {
      "LOG_LEVEL" = "info";
      "TZ" = "Europe/Paris";
    };
    ports = [
      "8191:8191/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=flaresolverr"
      "--network=seedbox_default"
    ];
  };

  # Service
  systemd.services."podman-flaresolverr" = {
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
