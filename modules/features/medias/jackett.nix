{ ... }:
{
  flake.modules.nixos.hyper = {
    services.flaresolverr.enable = true;
    services.mytraefik.services.jackett.port = 9117;
    services.jackett = {
      enable = true;
      dataDir = "/mnt/ultra/jackett";
    };
  };
}
