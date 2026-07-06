{ ... }:
let
  restoreCanaryModule =
    {
      pkgs,
      config,
      ...
    }:
    let
      inherit (config.restoreDrill.lib) reportLib commonPath;
    in
    {
      systemd.services.restore-canary = {
        description = "Weekly canary restore (zigbee ← Hetzner offsite)";
        startAt = "Sun 06:00";
        path = [
          pkgs.restic
          pkgs.openssh
          pkgs.sqlite
        ]
        ++ commonPath;
        serviceConfig = {
          Type = "oneshot";
          EnvironmentFile = config.age.secrets."restic.env".path;
        };
        script = ''
          source ${reportLib}
          TITLE="restore-canary (zigbee ← Hetzner)"
          REPO="sftp:${config.constants.hosts.hyper.storageBox.user}@${config.constants.hosts.hyper.storageBox.host}:/home/restic/zigbee2mqtt"
          DEST=/mnt/ultra/restore-test/zigbee
          rm -rf "$DEST"; mkdir -p "$DEST"

          restic -r "$REPO" restore latest --target "$DEST"
          add "snapshot restauré depuis Hetzner ✓"

          DB="$(find "$DEST" -name database.db | head -1)"
          [ -n "$DB" ] || { add "database.db introuvable"; exit 1; }
          RES="$(sqlite3 "$DB" 'PRAGMA integrity_check;')"
          add "database.db integrity_check: $RES"

          CB="$(find "$DEST" -name coordinator_backup.json | head -1)"
          [ -n "$CB" ] && add "coordinator_backup.json présent ✓"

          rm -rf "$DEST"
          [ "$RES" = ok ] || exit 1
        '';
      };
    };
in
{
  flake.modules.nixos.restoreDrill.imports = [ restoreCanaryModule ];
}
