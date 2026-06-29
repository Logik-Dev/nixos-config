{ ... }:
{
  flake.modules.nixos.sabnzbd =
    { lib, config, ... }:
    {
      traefik.services.sabnzbd.port = 8088;

      age.secrets."sabnzbd-credentials.ini" = {
        group = "media";
        mode = "0440";
      };

      notify.services = [ "sabnzbd" ];

      systemd.services.sabnzbd.serviceConfig.UMask = lib.mkForce "0002";

      services.sabnzbd = {
        enable = true;
        group = "media";
        configFile = null;
        stateDir = "sabnzbd";
        secretFiles = [ config.age.secrets."sabnzbd-credentials.ini".path ];
        settings = {
          misc = {
            port = 8088;
            host_whitelist = "sabnzbd.hyper.logikdev.fr";
            download_dir = "/mnt/storage/medias/downloads/incomplete";
            complete_dir = "/mnt/storage/medias/downloads";
            permissions = "770";
          };
          categories = {
            movies.dir = "movies";
            tv.dir = "series";
          };
        };
      };
    };
}
