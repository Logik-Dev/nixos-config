{ ... }:
{
  flake.modules.nixos.hyper =
    { hostSecret, config, ... }:
    {

      age.secrets."gluetun.env".rekeyFile = hostSecret "gluetun.env";

      services.mytraefik.services.torrent.port = 8080;

      systemd.tmpfiles.rules = [ "d /mnt/ultra/qbittorrent 775 logikdev media - -" ];

      virtualisation.oci-containers.containers = {
        gluetun = {
          image = "qmcgaw/gluetun";
          ports = [ "8080:8080" ];
          environmentFiles = [ config.age.secrets."gluetun.env".path ];
          extraOptions = [
            "--cap-add=NET_ADMIN"
            "--device=/dev/net/tun:/dev/net/tun"
          ];
        };

        qbittorrent = {
          image = "lscr.io/linuxserver/qbittorrent:latest";
          extraOptions = [ "--network=container:gluetun" ];
          dependsOn = [ "gluetun" ];
          volumes = [
            "/mnt/ultra/qbittorrent:/config"
            "/mnt/storage/medias/downloads:/mnt/storage/medias/downloads"
          ];
          environment = {
            PUID = "1000";
            PGID = "991";
            TZ = "Europe/Paris";
            WEBUI_PORT = "8080";
          };
        };
      };
    };

}
