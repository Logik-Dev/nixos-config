{ ... }:
let
  restoreCanaryModule =
    {
      pkgs,
      config,
      ...
    }:
    let
      inherit (config.restoreDrill.lib) reportLib drillStamp commonPath;

      # Derived from the backup config: renaming the source or dropping the
      # hetzner target now breaks evaluation instead of restoring the wrong repo.
      canarySource = "zigbee2mqtt";
      canaryRepo = "${
        config.backups.sources.${canarySource}.defaultRepositories.hetzner
      }/restic/${canarySource}";
    in
    {
      systemd.services.restore-canary = {
        description = "Weekly canary restore (zigbee ← Hetzner offsite)";
        startAt = "Sun 10:00";
        path = [
          pkgs.restic
          pkgs.openssh
          pkgs.sqlite
        ]
        ++ commonPath;
        unitConfig.RequiresMountsFor = [ "/mnt/ultra" ];
        serviceConfig = {
          Type = "oneshot";
          EnvironmentFile = config.age.secrets."restic.env".path;
          # restic restore needs a cache dir; with no HOME/XDG_CACHE_HOME it
          # aborts ("unable to locate cache directory").
          CacheDirectory = "restic-canary";
          Environment = [ "RESTIC_CACHE_DIR=/var/cache/restic-canary" ];
          ExecStopPost = [ "+${drillStamp} restore-canary" ];
        };
        script = ''
          source ${reportLib}
          TITLE="restore-canary (zigbee ← Hetzner)"
          REPO="${canaryRepo}"
          DEST=/mnt/ultra/restore-test/zigbee
          rm -rf "$DEST"; mkdir -p "$DEST"

          restic -r "$REPO" restore latest --target "$DEST"
          add "snapshot restauré depuis Hetzner ✓"

          DB="$(find "$DEST" -name database.db | head -1)"
          [ -n "$DB" ] || { add "database.db introuvable"; exit 1; }
          RES="$(sqlite3 "$DB" 'PRAGMA integrity_check;')"
          add "database.db integrity_check: $RES"

          CB="$(find "$DEST" -name coordinator_backup.json | head -1)"
          [ -n "$CB" ] || { add "coordinator_backup.json introuvable"; exit 1; }
          add "coordinator_backup.json présent ✓"

          rm -rf "$DEST"
          [ "$RES" = ok ] || exit 1
        '';
      };
    };
in
{
  flake.modules.nixos.restoreDrill.imports = [ restoreCanaryModule ];
}
