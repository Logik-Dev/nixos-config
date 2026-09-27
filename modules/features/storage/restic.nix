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

      # Single source of truth for the (source × repository) → path mapping:
      # the backup jobs here, the restic exporters (monitoring/restic.nix) and
      # the restore drills (restore-drill/*) all consume it instead of
      # re-deriving `<target>/restic/<source>`.
      repositories = lib.mapAttrs (
        sourceName: sourceValue:
        lib.mapAttrs (_targetName: targetPath: "${targetPath}/restic/${sourceName}") (
          sourceValue.defaultRepositories // sourceValue.extraRepositories
        )
      ) cfg.sources;

      # One job per (source × repository). Computed once so the backup
      # definitions, the notify units and the systemd guards stay in sync.
      jobs = lib.flatten (
        lib.mapAttrsToList (
          sourceName: sourceValue:
          lib.mapAttrsToList (targetName: targetPath: {
            name = "${sourceName}-${targetName}";
            inherit
              sourceName
              sourceValue
              targetName
              targetPath
              ;
          }) (sourceValue.defaultRepositories // sourceValue.extraRepositories)
        ) cfg.sources
      );

      mkBackup =
        job:
        let
          inherit (job)
            sourceName
            sourceValue
            targetName
            ;
          serviceName =
            if (lib.isString sourceValue.serviceName) then sourceValue.serviceName else sourceName;
        in
        {
          inherit (sourceValue) paths;
          inherit (sourceValue) exclude;
          # Bound the per-job cache on the root filesystem (26 jobs would
          # otherwise grow /var/cache without limit).
          extraBackupArgs = [ "--cleanup-cache" ];
          initialize = true;
          environmentFile = config.age.secrets."restic.env".path;
          repository = repositories.${sourceName}.${targetName};
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
            lib.optional sourceValue.manageService "${config.systemd.package}/bin/systemctl stop ${serviceName}.service"
            ++ lib.optional (sourceValue.runBefore != null) sourceValue.runBefore
          );
        }
        // lib.optionalAttrs sourceValue.manageService {
          # Targets of the same source can overlap (5h random spread): only
          # restart the service when no other *service* (--type=service skips
          # the always-active timers, which would otherwise match the glob) is
          # still backing up, and serialize the check with flock so two
          # cleanups cannot both skip.
          backupCleanupCommand = ''
            {
              ${pkgs.util-linux}/bin/flock 9
              others="$(${config.systemd.package}/bin/systemctl list-units --type=service --state=active --no-legend 'restic-backups-${sourceName}-*' | ${pkgs.gnugrep}/bin/grep -v 'restic-backups-${sourceName}-${targetName}.service' || true)"
              [ -n "$others" ] || ${config.systemd.package}/bin/systemctl start ${serviceName}.service
            } 9>/run/restic-${sourceName}.start.lock
          '';
        };

      # Data disks are mounted with `nofail`: without an explicit mount
      # dependency a missing /mnt/usb or /mnt/ultra would silently redirect the
      # backup to the root filesystem (tmpfiles recreate the target dirs, and
      # `initialize = true` happily creates a brand-new repo there). Requiring
      # the mounts makes the job fail loudly instead (onFailure is wired to
      # ntfy since P0-3). sftp targets need no local mount.
      mkUnitOverride = job: {
        unitConfig.RequiresMountsFor =
          lib.optional (lib.hasPrefix "/" job.targetPath) job.targetPath ++ job.sourceValue.paths;
      };

      source = lib.types.submodule {
        options = {
          paths = lib.mkOption {
            description = "List of paths to backup";
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
          exclude = lib.mkOption {
            description = "Patterns to exclude from the backup";
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
          defaultRepositories = lib.mkOption {
            description = "Default repositories";
            type = lib.types.attrs;
            default = {
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
        repositories = lib.mkOption {
          description = "Computed (source × repository) → repository path map, shared by backups, exporters and drills";
          type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
          readOnly = true;
        };
      };

      config = {
        backups.repositories = repositories;

        environment.systemPackages = [ pkgs.restic ];

        systemd.tmpfiles.rules = [ "d /mnt/usb/restic 0755 root root -" ];

        notify.services = map (job: "restic-backups-${job.name}") jobs;

        services.restic.backups = lib.listToAttrs (
          map (job: lib.nameValuePair job.name (mkBackup job)) jobs
        );

        systemd.services = lib.listToAttrs (
          map (job: lib.nameValuePair "restic-backups-${job.name}" (mkUnitOverride job)) jobs
        );
      };
    };

in
{
  inherit flake;
}
