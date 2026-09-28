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
      # the backup jobs, the restore drills (restore-drill/*) and the Grafana
      # labels all consume it instead of re-deriving `<target>/restic/<source>`.
      # Two targets only: usb = dedicated external disk (on-site), hetzner =
      # Storage Box (off-site). There is no third on-site copy: /mnt/local is a
      # LV of the system disk, i.e. not a distinct failure domain.
      repositories = lib.mapAttrs (sourceName: _: {
        usb = "/mnt/usb/restic/${sourceName}";
        hetzner = "sftp:${sb.user}@${sb.host}:/home/restic/${sourceName}";
      }) cfg.sources;

      metricsLib = import ../monitoring/lib/_restic-metrics.nix { inherit pkgs; };

      # One systemd unit per source (not per repo): the ExecStart script below
      # backs up to usb then hetzner sequentially and emits push metrics. This
      # removes the per-repo job fan-out and with it the flock/refcount dance
      # that used to avoid concurrent stop/start of the same service.
      mkScript =
        sourceName: sourceValue:
        let
          excludes =
            lib.optionalString (sourceValue.exclude != [ ])
              "--exclude-file ${pkgs.writeText "restic-exclude-${sourceName}" (lib.concatLines sourceValue.exclude)}";
        in
        pkgs.writeShellScript "restic-backup-${sourceName}" ''
          source ${metricsLib}
          set -Eeuo pipefail

          # Paths were collected by the nixpkgs restic module in ExecStartPre.
          INCLUDES=/run/restic-backups-${sourceName}/includes
          fail=0

          backup_repo() {
            key="$1"; repo="$2"
            # A fresh repo has no config yet; unlock clears any stale exclusive
            # lock left by a backup killed mid-run (e.g. a switch during the
            # nightly job), which otherwise stalls every later run.
            restic -r "$repo" cat config >/dev/null 2>&1 || restic -r "$repo" init
            restic -r "$repo" unlock
            if restic -r "$repo" backup --files-from "$INCLUDES" ${excludes} --cleanup-cache; then
              restic -r "$repo" forget --prune \
                --keep-daily 7 --keep-weekly 3 --keep-monthly 6 --keep-yearly 2
              emit_restic_metrics "${sourceName}" "$key" "$repo"
            else
              fail=1
            fi
          }

          backup_repo usb ${lib.escapeShellArg repositories.${sourceName}.usb}
          backup_repo hetzner ${lib.escapeShellArg repositories.${sourceName}.hetzner}

          exit "$fail"
        '';

      mkBackup =
        sourceName: sourceValue:
        let
          serviceName =
            if (lib.isString sourceValue.serviceName) then sourceValue.serviceName else sourceName;
        in
        {
          inherit (sourceValue) paths;
          inherit (sourceValue) exclude;
          initialize = true;
          environmentFile = config.age.secrets."restic.env".path;
          repository = repositories.${sourceName}.usb;
          timerConfig = {
            OnCalendar = "02:05";
            Persistent = true;
            RandomizedDelaySec = "5h";
          };
        }
        // lib.optionalAttrs sourceValue.manageService {
          backupPrepareCommand = "${config.systemd.package}/bin/systemctl stop ${serviceName}.service";
          backupCleanupCommand = "${config.systemd.package}/bin/systemctl start ${serviceName}.service";
        };

      # Data disks are mounted with `nofail`: without an explicit mount
      # dependency a missing /mnt/usb would silently redirect the backup to the
      # root filesystem (tmpfiles recreate the target dir, and `initialize = true`
      # happily creates a brand-new repo there). Requiring the mount makes the
      # job fail loudly instead (onFailure is wired to ntfy). sftp needs no mount.
      mkUnitOverride = sourceName: sourceValue: {
        path = [
          pkgs.restic
          pkgs.jq
          pkgs.coreutils
        ];
        unitConfig.RequiresMountsFor = [ "/mnt/usb" ] ++ sourceValue.paths;
        serviceConfig = {
          ExecStart = lib.mkForce [
            (toString (mkScript sourceName sourceValue))
          ];

          # Backups are the second source of measured IO pressure after
          # snapraid, and their window (02:05 + up to 5h of random delay) can
          # still overlap late-evening streaming. These three settings only
          # became effective with BFQ on the rotational disks — see
          # system/io-scheduler.nix; on the NVMe sources the scheduler is "none"
          # and IOSchedulingClass is a no-op.
          #
          # idle IO rather than best-effort is safe here, unlike for nix-daemon:
          # nothing else competes inside the nightly window except the other
          # restic jobs, which are in the same class and so share fairly.
          # Nice/batch keeps restic's compression and encryption off the latency
          # path of Jellyfin and Postgres.
          Nice = 19;
          CPUSchedulingPolicy = "batch";
          IOSchedulingClass = "idle";
        };
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
          manageService = lib.mkOption {
            description = "Stop and restart the service around the backup";
            type = lib.types.bool;
            default = true;
          };
          serviceName = lib.mkOption {
            description = "Optional service name, if null default to source name";
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
        };
      };

      sourceNames = lib.attrNames cfg.sources;
    in
    {
      options.backups = {
        sources = lib.mkOption {
          description = "Attribute set of sources";
          type = lib.types.attrsOf source;
          default = { };
        };
        repositories = lib.mkOption {
          description = "Computed (source × repository) → repository path map, shared by backups, drills and dashboards";
          type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
          readOnly = true;
        };
      };

      config = {
        backups.repositories = repositories;

        environment.systemPackages = [ pkgs.restic ];

        systemd.tmpfiles.rules = [ "d /mnt/usb/restic 0755 root root -" ];

        notify.services = map (name: "restic-backups-${name}") sourceNames;

        services.restic.backups = lib.mapAttrs mkBackup cfg.sources;

        systemd.services = lib.mapAttrs' (
          name: value: lib.nameValuePair "restic-backups-${name}" (mkUnitOverride name value)
        ) cfg.sources;
      };
    };

in
{
  inherit flake;
}
