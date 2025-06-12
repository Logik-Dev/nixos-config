{ pkgs }:
let

  # concat services with space between
  joinServices = services: builtins.concatStringsSep " " services;

  # start/stop services
  doServices =
    action: services:
    if services == [ ] then
      pkgs.writeShellScriptBin "${action}-services" ''
        echo 'No service to ${action}, skipping...'
      ''
    else
      pkgs.writeShellScriptBin "${action}-services" ''
        echo '${action} services ${joinServices services}...'
        sudo systemctl ${action} ${joinServices services}
      '';

  # start services
  startServices = services: doServices "start" services;

  # stop services
  stopServices = services: doServices "stop" services;

  # restore directories
  restoreDirectories =
    config: directories:
    if directories == [ ] then
      pkgs.writeShellScriptBin "restore-directories" ''
        echo "No directories to restore, skipping..."
      ''
    else
      pkgs.writeShellScriptBin "restore-directories" ''
        echo "Restore ${config} directories..."
        sudo borgmatic extract  --config /etc/borgmatic.d/${config}.yaml --archive latest --destination /
      '';

  # restore postgresql databases
  restorePostgresql =
    config: dbs:
    if dbs == [ ] then
      pkgs.writeShellScriptBin "restore-databases" ''
        echo 'No database to restore'
      ''
    else
      pkgs.writeShellScriptBin "restore-databases" ''
        echo 'Restore database for ${config}...'
        sudo borgmatic restore --config /etc/borgmatic.d/${config}.yaml --archive latest
      '';

in
{
  inherit
    startServices
    stopServices
    restorePostgresql
    restoreDirectories
    ;
}
