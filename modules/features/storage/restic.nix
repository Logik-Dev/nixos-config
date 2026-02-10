{ inputs, ... }:
let
  flake.modules.nixos.hyper = {
    imports = [ inputs.self.modules.nixos.restic ];
    services.backups.enable = true;
  };

  flake.modules.nixos.restic =
    {
      lib,
      config,
      commonSecret,
      ...
    }:

    with lib;
    let
      cfg = config.services.backups;

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

        };
      };
    in
    {
      options.services.backups = {
        enable = mkEnableOption "Enable restic backups";
        sources = mkOption {
          description = "Attribute set of sources";
          type = types.attrsOf source;
          default = { };
        };
      };

      config = mkIf cfg.enable {
        age.secrets."restic.env".rekeyFile = commonSecret "restic.env";
        systemd.tmpfiles.rules = [ "d /mnt/usb/restic 0755 root root -" ];

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
