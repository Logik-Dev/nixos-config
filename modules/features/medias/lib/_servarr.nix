{ pkgs }:
{
  app,
  mainDb,
  logDb,
}:
{ lib, ... }:
let
  prefix = lib.toUpper app;
  env = pkgs.writeText "${app}.env" ''
    ${prefix}__POSTGRES__HOST=/var/run/postgresql
    ${prefix}__POSTGRES__PORT="5432"
    ${prefix}__POSTGRES__USER=${app}
    ${prefix}__POSTGRES__MAINDB=${mainDb}
    ${prefix}__POSTGRES__LOGDB=${logDb}
  '';
in
{
  services.postgresql = {
    ensureDatabases = [
      logDb
      mainDb
    ];
    ensureUsers = [
      {
        name = app;
      }
    ];
  };

  services.${app}.environmentFiles = [ env ];
}
