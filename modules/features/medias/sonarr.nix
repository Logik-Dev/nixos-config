{ ... }:
{
  flake.modules.nixos.hyper =
    { pkgs, config, ... }:
    let
      sonarrEnv = pkgs.writeText "sonarr.env" ''
        SONARR__POSTGRES__HOST=/var/run/postgresql
        SONARR__POSTGRES__PORT="5432"
        SONARR__POSTGRES__USER=sonarr
        SONARR__POSTGRES__MAINDB=sonarr-main
        SONARR__POSTGRES__LOGDB=sonarr-logs
      '';
    in

    {
      services.postgresql = {
        ensureDatabases = [
          "sonarr-logs"
          "sonarr-main"
        ];
        ensureUsers = [
          {
            name = "sonarr";
          }
        ];
      };

      services.mytraefik.services.sonarr.port = 8989;
      services.mytraefik.services.sonarr.enableAuthelia = true;

      services.sonarr = {
        enable = true;
        group = "media";
        environmentFiles = [ sonarrEnv ];
        dataDir = "/mnt/ultra/sonarr";
      };

      services.backups.sources.sonarr = {
        paths = [ config.services.sonarr.dataDir ];
        extraRepositories.local = "/mnt/local";
      };
    };
}
