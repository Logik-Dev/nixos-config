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
      services.mytraefik.services.unifi = {
        port = 8443;
        protocol = "https";
      };
    };
}
