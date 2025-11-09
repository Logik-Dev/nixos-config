{ ... }:
{
  flake.modules.nixos.hyper =
    { pkgs, ... }:
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

      services.reverse-proxy.vhosts.sonarr.port = 8989;

      services.sonarr = {
        enable = true;
        environmentFiles = [ sonarrEnv ];
        dataDir = "/mnt/ultra/sonarr";
      };
    };
}
