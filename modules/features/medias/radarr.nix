{ ... }:
{
  flake.modules.nixos.hyper =
    { pkgs, lib, ... }:
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

      services.mytraefik.services.radarr.port = 7878;

      services.radarr = {
        enable = true;
        environmentFiles = [ radarrEnv ];
        dataDir = "/mnt/ultra/radarr";
      };
    };
}
