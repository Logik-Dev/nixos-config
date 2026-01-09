{
  flake.modules.nixos.unifi = {
    services.unifi.enable = true;
    services.mytraefik.services.unifi = {
      port = 8443;
      protocol = "https";
    };
  };
}
