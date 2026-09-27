{
  flake.modules.nixos.unifi =
    { pkgs, ... }:
    {
      networking.firewall.allowedTCPPorts = [ 8080 ];
      networking.firewall.allowedUDPPorts = [
        10001
        3478
      ];

      services.unifi.enable = true;
      services.unifi.mongodbPackage = pkgs.mongodb-ce;

      notify.services = [ "unifi" ];

      # UniFi writes self-consistent .unf backups here; grab those live instead
      # of stopping the slow controller + embedded mongo (raw mongo files would
      # be inconsistent anyway). Restore via the controller's "Restore" UI.
      backups.sources.unifi = {
        paths = [ "/var/lib/unifi/data/backup/autobackup" ];
        manageService = false;
      };

      traefik.services.unifi = {
        port = 8443;
        protocol = "https";
        insecureSkipVerify = true;
        enableAuthelia = true;
        category = "Réseau & Stockage";
        icon = "di:unifi";
      };
    };
}
