{ ... }:
{
  flake.modules.nixos.hyper =
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

      services.reverse-proxy.vhosts.prowlarr.port = 9696;

      services.prowlarr = {
        enable = true;
        environmentFiles = [ prowlarrEnv ];
        dataDir = "/mnt/ultra/prowlarr";
      };
    };
}
