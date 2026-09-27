_:
let
  resticVerifyModule =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      inherit (config.restoreDrill.lib)
        reportLib
        drillStamp
        commonPath
        repoLines
        ;

      # Derived from the backup config: renaming the source or dropping the
      # hetzner target now breaks evaluation instead of restoring the wrong repo.
      canarySource = "zigbee2mqtt";
      canaryRepo = config.backups.repositories.${canarySource}.hetzner;
    in
    {
      systemd.services.restic-verify = {
        description = "Weekly restic integrity check, offsite canary restore and rotating read-data";
        # 10:00: after the 02:05-07:05 backup window, the 01:30 pg_dumpall and the
        # 03:30 pgBackRest full.
        startAt = "Sun 10:00";
        path = [
          pkgs.restic
          pkgs.openssh
          pkgs.sqlite
        ]
        ++ commonPath;
        unitConfig.RequiresMountsFor = [
          "/mnt/usb"
          "/mnt/ultra"
        ];
        serviceConfig = {
          Type = "oneshot";
          EnvironmentFile = config.age.secrets."restic.env".path;
          # Reads full blobs from the small usb/hetzner repos, a 10% slice of
          # immich (~44 GB over sftp) and restores the zigbee repo offsite.
          TimeoutStartSec = "6h";
          # restic needs a cache dir; with no HOME/XDG_CACHE_HOME it aborts
          # ("unable to locate cache directory").
          CacheDirectory = "restic-verify";
          Environment = [ "RESTIC_CACHE_DIR=/var/cache/restic-verify" ];
          ExecStopPost = [ "+${drillStamp} restic-verify" ];
        };
        script = ''
          source ${reportLib}
          TITLE="restic-verify"

          # Push the check result into the node-exporter textfile so the
          # ResticCheckFailed rule and the Grafana panel keep working without
          # the removed exporter.
          dir=/var/lib/node-exporter-textfile
          mkdir -p "$dir"; umask 022
          tmp="$dir/.restic-check.prom.tmp"
          : > "$tmp"

          OK=0; KO=0; FAILED=0
          LOG="$(mktemp)"
          while read -r name repo mode; do
            [ -z "$name" ] && continue
            if [ "$mode" = full ]; then
              args="check --read-data --retry-lock 30m"
            else
              args="check --read-data-subset=10% --retry-lock 30m"
            fi
            if restic -r "$repo" $args >"$LOG" 2>&1; then
              OK=$((OK + 1)); ok=1
            else
              KO=$((KO + 1)); FAILED=1; ok=0
              add "✗ $name ($mode)"
              add "$(tail -n 3 "$LOG")"
            fi
            printf 'restic_check_success{repository="%s"} %s\n' "$name" "$ok" >> "$tmp"
          done <<'REPOS'
          ${repoLines}
          REPOS
          mv -f "$tmp" "$dir/restic-check.prom"
          add "repos OK: $OK — KO: $KO (immich = slice 10%)"

          # Offsite canary: restore a real repo from Hetzner and verify its DB.
          DEST=/mnt/ultra/restore-test/zigbee
          rm -rf "$DEST"; mkdir -p "$DEST"
          restic -r ${lib.escapeShellArg canaryRepo} restore latest --target "$DEST"
          add "snapshot ${canarySource} restauré depuis Hetzner ✓"

          DB="$(find "$DEST" -name database.db | head -1)"
          [ -n "$DB" ] || { add "database.db introuvable"; exit 1; }
          RES="$(sqlite3 "$DB" 'PRAGMA integrity_check;')"
          add "database.db integrity_check: $RES"

          CB="$(find "$DEST" -name coordinator_backup.json | head -1)"
          [ -n "$CB" ] || { add "coordinator_backup.json introuvable"; exit 1; }
          add "coordinator_backup.json présent ✓"

          rm -rf "$DEST"
          [ "$RES" = ok ] || exit 1
          exit $FAILED
        '';
      };
    };
in
{
  flake.modules.nixos.restoreDrill.imports = [ resticVerifyModule ];
}
