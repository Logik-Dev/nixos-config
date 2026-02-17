{ ... }:
{
  flake.modules.nixos.radarr =
    { pkgs, config, ... }:
    let
      radarrEnv = pkgs.writeText "radarr.env" ''
        RADARR__POSTGRES__HOST=/var/run/postgresql
        RADARR__POSTGRES__PORT="5432"
        RADARR__POSTGRES__USER=radarr
        RADARR__POSTGRES__MAINDB=radarr-main
        RADARR__POSTGRES__LOGDB=radarr-logs
      '';
    in

    {
      services.postgresql = {

        ensureDatabases = [
          "radarr-logs"
          "radarr-main"
        ];
        ensureUsers = [
          {
            name = "radarr";
          }
        ];
      };

      traefik.services.radarr.port = 7878;
      traefik.services.radarr.enableAuthelia = true;

      services.radarr = {
        enable = true;
        group = "media";
        environmentFiles = [ radarrEnv ];
        dataDir = "/mnt/ultra/radarr";
      };

      backups.sources.radarr = {
        paths = [ config.services.radarr.dataDir ];
        extraRepositories.local = "/mnt/local";
      };
    };
}
