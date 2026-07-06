let
  flake.modules.nixos.restic =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.backups;
      sb = config.constants.hosts.hyper.storageBox;

      source = lib.types.submodule {
        options = {
          paths = lib.mkOption {
            description = "List of paths to backup";
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
          defaultRepositories = lib.mkOption {
            description = "Default repositories";
            type = lib.types.attrs;
            default = {
              # No on-site object-store target anymore: the old `s3` (rustfs)
              # repo lived on the same disk as the sources, so it only ever
              # protected against accidental deletion — usb + hetzner already
              # cover that and more. rustfs was decommissioned 2026-07-04.
              usb = "/mnt/usb";
              # Offsite copy on the Hetzner Storage Box (SFTP backend). SSH
              # client config + pinned host key live in
              # modules/features/storage/hetzner-storagebox.nix.
              # The box's writable storage is exposed at /home (real "/" is
              # read-only), so the base must be /home; yields repository
              # sftp:...:/home/restic/<source> per source.
              hetzner = "sftp:${sb.user}@${sb.host}:/home";
            };
          };
          extraRepositories = lib.mkOption {
            description = "Extra repositories";
            type = lib.types.attrs;
            default = { };
          };
          manageService = lib.mkOption {
            description = "Stop and restart the service";
            type = lib.types.bool;
            default = true;
          };
          serviceName = lib.mkOption {
            description = "Optional service name, if null default to source name";
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          runBefore = lib.mkOption {
            description = "Command to run before backup";
            type = lib.types.nullOr lib.types.str;
            default = null;
          };

        };
      };
    in
    {
      options.backups = {
        sources = lib.mkOption {
          description = "Attribute set of sources";
          type = lib.types.attrsOf source;
          default = { };
        };
      };

      config = {

        environment.systemPackages = [ pkgs.restic ];

        systemd.tmpfiles.rules = [ "d /mnt/usb/restic 0755 root root -" ];

        notify.services = [ "restic" ];

        services.restic.backups = lib.mkMerge (
          lib.flatten (
            lib.mapAttrsToList (
              sourceName: sourceValue:
              lib.mapAttrsToList (targetName: targetPath: {
                "${sourceName}-${targetName}" =
                  let
                    serviceName =
                      if (lib.isString sourceValue.serviceName) then sourceValue.serviceName else sourceName;
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
                    // lib.optionalAttrs (sourceValue.manageService || sourceValue.runBefore != null) {
                      backupPrepareCommand = lib.concatStringsSep "\n" (
                        lib.optional sourceValue.manageService "systemctl stop ${serviceName}.service"
                        ++ lib.optional (sourceValue.runBefore != null) sourceValue.runBefore
                      );
                    }
                    // lib.optionalAttrs sourceValue.manageService {
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
