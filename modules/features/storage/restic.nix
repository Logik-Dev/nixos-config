let
  flake.modules.nixos.restic =
    {
      lib,
      config,
      pkgs,
      ...
    }:

    with lib;
    let
      cfg = config.backups;

      source = types.submodule {
        options = {
          paths = mkOption {
            description = "List of paths to backup";
            type = types.listOf types.str;
            default = [ ];
          };
          defaultRepositories = mkOption {
            description = "Default repositories";
            type = types.attrs;
            default = {
              s3 = "s3:https://s3.hyper.logikdev.fr";
              usb = "/mnt/usb";
            };
          };
          extraRepositories = mkOption {
            description = "Extra repositories";
            type = types.attrs;
            default = { };
          };
          manageService = mkOption {
            description = "Stop and restart the service";
            type = types.bool;
            default = true;
          };
          serviceName = mkOption {
            description = "Optional service name, if null default to source name";
            type = types.nullOr types.str;
            default = null;
          };
          runBefore = mkOption {
            description = "Command to run before backup";
            type = types.nullOr types.str;
            default = null;
          };

        };
      };
    in
    {
      options.backups = {
        sources = mkOption {
          description = "Attribute set of sources";
          type = types.attrsOf source;
          default = { };
        };
      };

      config = {

        environment.systemPackages = [ pkgs.restic ];

        systemd.tmpfiles.rules = [ "d /mnt/usb/restic 0755 root root -" ];

        notify.services = [ "restic" ];

        services.restic.backups = mkMerge (
          flatten (
            mapAttrsToList (
              sourceName: sourceValue:
              mapAttrsToList (targetName: targetPath: {
                "${sourceName}-${targetName}" =
                  let
                    serviceName = if (isString sourceValue.serviceName) then sourceValue.serviceName else sourceName;
                  in
                  (
                    {
                      paths = sourceValue.paths;
                      initialize = true;
                      environmentFile = config.age.secrets."restic.env".path;
                      repository = "${targetPath}/restic/${sourceName}";
                      timerConfig = {
                        OnCalendar = "02:05";
                        Persistent = true;
                        RandomizedDelaySec = "5h";
                      };
                      pruneOpts = [
                        "--keep-daily 7"
                        "--keep-weekly 3"
                        "--keep-monthly 6"
                        "--keep-yearly 2"
                      ];
                    }
                    # Stop service before and restart it after
                    // optionalAttrs sourceValue.manageService {
                      backupPrepareCommand = "systemctl stop ${serviceName}.service";
                      backupCleanupCommand = "systemctl start ${serviceName}.service";
                    }
                    // optionalAttrs (sourceValue.runBefore != null) {
                      backupPrepareCommand = sourceValue.runBefore;
                    }
                  );
              }) (sourceValue.defaultRepositories // sourceValue.extraRepositories)
            ) cfg.sources
          )
        );
      };
    };

in
{
  inherit flake;
}
