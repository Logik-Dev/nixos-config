{
  flake.modules.nixos.unifi = {
    services.unifi.enable = true;
    services.reverse-proxy.vhosts.unifi = {
      port = 8443;
      protocol = "https";
    };
  };
}
