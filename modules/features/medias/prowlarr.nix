{ ... }:
{
  flake.modules.nixos.prowlarr =
    { pkgs, ... }:
    let
      prowlarrEnv = pkgs.writeText "prowlarr.env" ''
        PROWLARR__POSTGRES__HOST=/var/run/postgresql
        PROWLARR__POSTGRES__PORT="5432"
        PROWLARR__POSTGRES__USER=prowlarr
        PROWLARR__POSTGRES__MAINDB=prowlarr-main
        PROWLARR__POSTGRES__LOGDB=prowlarr-logs
      '';
    in

    {
      services.postgresql = {

        ensureDatabases = [
          "prowlarr-logs"
          "prowlarr-main"
        ];
        ensureUsers = [
          {
            name = "prowlarr";
          }
        ];
      };

      traefik.services.prowlarr.port = 9696;
      traefik.services.prowlarr.enableAuthelia = true;

      services.prowlarr = {
        enable = true;
        environmentFiles = [ prowlarrEnv ];
        dataDir = "/mnt/ultra/prowlarr";
      };
    };
}
