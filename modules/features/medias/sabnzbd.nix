{ ... }:
{
  flake.modules.nixos.sabnzbd =
    { config, ... }:
    {
      imports = [ (import ./lib/_media-service.nix { app = "sabnzbd"; }) ];

      traefik.services.sabnzbd = {
        port = 8088;
        enableAuthelia = true;
        category = "Médias";
        icon = "di:sabnzbd";
      };

      age.secrets."sabnzbd-credentials.ini" = {
        group = "media";
        mode = "0440";
      };

      notify.services = [ "sabnzbd" ];

      # Config, history and queue state in /var/lib/sabnzbd; stopped during
      # the backup for a consistent copy.
      backups.sources.sabnzbd = {
        paths = [ "/var/lib/sabnzbd" ];
      };

      services.sabnzbd = {
        enable = true;
        configFile = null;
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
