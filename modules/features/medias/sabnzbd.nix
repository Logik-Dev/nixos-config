{ ... }:
{
  flake.modules.nixos.sabnzbd =
    { config, ... }:
    {
      traefik.services.sabnzbd.port = 8082;
      services.sabnzbd = {
        enable = true;
        settings = {
          misc.port = 8082;
          secretFiles = [ config.age.secrets."sabnzbd-credentials.ini".path ];
          servers.eweka = {
            port = 563;
            name = "eweka";
            host = "news.eweka.nl";
            connections = 50;
          };
        };
      };
    };
}
