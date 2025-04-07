{
  homelab,
  lib,
  pkgs,
  ...
}:
{
  imports = [ ./ha ];

  networking.networkmanager.enable = lib.mkForce false;

  services.unifi = {
    enable = true;
    mongodbPackage = pkgs.mongodb-ce;
  };

  services.nginx.virtualHosts."unifi.${homelab.domain}" = {
    enableACME = true;
    forceSSL = true;
    acmeRoot = null;
    locations."/" = {
      proxyPass = "https://localhost:8443";
    };
  };

  system.stateVersion = lib.mkForce "24.11";
}
