{ ... }:
{
  flake.modules.nixos.hyper = {
    services = {
      jellyseerr.enable = true;
      mytraefik.services.jellyseerr.port = 5055;
    };
  };
}
