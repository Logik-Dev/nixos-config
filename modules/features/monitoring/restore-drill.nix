{
  flake.modules.nixos.restoreDrill =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      pg = config.services.postgresql.finalPackage;

      # One line per (source × repository), space-separated: "<name> <repo> <mode>".
      # immich (~440 GB) is too large for a weekly full --read-data. In the
      # weekly restic-check it gets a structural `restic check` only; its
      # blob-level verification is done incrementally by restic-read-data below
      # (a rotating slice). Everything else is small, so full --read-data is cheap.
      # (rustfs used to be here too, but the wholesale rustfs-usb backup was
      # dropped — it just duplicated immich; see rustfs.nix / postgresql.nix.)
      bigSources = [
        "immich"
      ];
      resticRepos = lib.flatten (
        lib.mapAttrsToList (
          sourceName: sourceValue:
          lib.mapAttrsToList (_targetName: targetPath: {
            name = "${sourceName}-${_targetName}";
            repository = "${targetPath}/restic/${sourceName}";
            mode = if lib.elem sourceName bigSources then "struct" else "full";
          }) (sourceValue.defaultRepositories // sourceValue.extraRepositories)
        ) config.backups.sources
      );
      repoLines = lib.concatMapStringsSep "\n" (r: "${r.name} ${r.repository} ${r.mode}") resticRepos;

      # The big repos, for restic-read-data's rotating slice check.
      bigRepoLines = lib.concatMapStringsSep "\n" (r: "${r.name} ${r.repository}") (
        lib.filter (r: r.mode == "struct") resticRepos
      );

      # Sourced by every drill: accumulates a human-readable body with add(),
      # then posts ONE formatted message to the dedicated backup-verify topic on
      # exit — success (✅) and failure (❌) alike, so the weekly run doubles as a
      # heartbeat (silence means the timer itself didn't fire).
      reportLib = pkgs.writeText "backup-verify-report.sh" ''
        BODY=""
        add() { BODY="''${BODY}$1
        "; }
        _finish() {
          rc=$?
          if [ "$rc" -eq 0 ]; then
            head="✅ ''${TITLE:-drill} — OK"; prio=default; tags=white_check_mark
          else
            head="❌ ''${TITLE:-drill} — ÉCHEC (rc=$rc)"; prio=high; tags=rotating_light
          fi
          printf '%s\n\n%s' "$head" "$BODY" | ${pkgs.curl}/bin/curl -s \
            -H "Title: Backup verify" -H "Priority: $prio" -H "Tags: $tags" \
            --data-binary @- "http://localhost:2586/backup-verify" >/dev/null 2>&1 || true
        }
        trap _finish EXIT
        set -Eeuo pipefail
      '';

      commonPath = [
        pkgs.coreutils
        pkgs.gnutar
        pkgs.gawk
        pkgs.findutils
        pkgs.curl
      ];
    in
    {
      # postgres-restore-drill runs as the postgres user; give it a writable base.
      systemd.tmpfiles.rules = [ "d /mnt/ultra/restore-test 0700 postgres postgres -" ];

      systemd.services = {
        # 1. Integrity of every restic repo. `restic check` (structure) always;
        #    `--read-data` (re-decrypts real blobs, catches silent corruption)
        #    for everything except the big repo (immich), covered incrementally
        #    by restic-read-data.
        restic-check = {
          description = "Weekly integrity check of all restic repositories";
          startAt = "Sun 05:00";
          path = [
            pkgs.restic
            pkgs.openssh
          ]
          ++ commonPath;
          serviceConfig = {
            Type = "oneshot";
            EnvironmentFile = config.age.secrets."restic.env".path;
          };
          script = ''
            source ${reportLib}
            TITLE="restic-check"
            OK=0; KO=0; FAILED=0
            LOG="$(mktemp)"
            while read -r name repo mode; do
              [ -z "$name" ] && continue
              if [ "$mode" = full ]; then args="check --read-data"; else args="check"; fi
              if restic -r "$repo" $args >"$LOG" 2>&1; then
                OK=$((OK + 1))
              else
                KO=$((KO + 1)); FAILED=1
                add "✗ $name ($mode)"
                add "$(tail -n 3 "$LOG")"
              fi
            done <<'REPOS'
            ${repoLines}
            REPOS
            add "repos OK: $OK — KO: $KO"
            add "(immich = structurel seul ici, read-data via restic-read-data)"
            exit $FAILED
          '';
        };

        # 2. Real end-to-end restore of a self-contained source (zigbee: SQLite,
        #    no postgres dependency) from the OFFSITE Hetzner repo — the least
        #    exercised target. Proves the SSH key + sftp path + decryption chain.
        restore-canary = {
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
            REPO="sftp:u625917@u625917.your-storagebox.de:/home/restic/zigbee2mqtt"
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

        # 3. The big one: real barman restore of postgres into a throwaway
        #    instance (isolated: alt socket, archiving off, recovery_target
        #    immediate), then query real tables. Covers vaultwarden + prowlarr +
        #    immich metadata, which all live in postgres.
        postgres-restore-drill = {
          description = "Weekly postgres restore drill (barman → throwaway instance)";
          startAt = "Sun 07:00";
          path = commonPath;
          serviceConfig = {
            Type = "oneshot";
            User = "postgres";
            Group = "postgres";
            EnvironmentFile = config.age.secrets."s3.env".path;
            TimeoutStartSec = "20min";
          };
          script = ''
            source ${reportLib}
            TITLE="postgres-restore-drill"
            B=${pkgs.barman}/bin
            P=${pg}/bin
            EP=http://localhost:9000; S3=s3://pg-backups; SRV=pg-16
            ROOT=/mnt/ultra/restore-test; RDIR=$ROOT/pg; SOCK=$ROOT/sock
            rm -rf "$RDIR" "$SOCK"; mkdir -p "$RDIR" "$SOCK"

            BID="$("$B"/barman-cloud-backup-list --cloud-provider aws-s3 --endpoint-url "$EP" "$S3" "$SRV" | tail -1 | awk '{print $1}')"
            add "base backup: $BID"

            "$B"/barman-cloud-restore --cloud-provider aws-s3 --endpoint-url "$EP" "$S3" "$SRV" "$BID" "$RDIR"

            cat >> "$RDIR/postgresql.auto.conf" <<CONF
            restore_command = '$B/barman-cloud-wal-restore --cloud-provider aws-s3 --endpoint-url $EP $S3 $SRV %f %p'
            recovery_target = 'immediate'
            recovery_target_action = 'promote'
            archive_mode = off
            hot_standby = on
            port = 5433
            unix_socket_directories = '$SOCK'
            CONF
            touch "$RDIR/recovery.signal"
            chmod 700 "$RDIR"

            "$P"/pg_ctl -D "$RDIR" -w -t 600 -l "$RDIR/startup.log" start

            st=x
            for _ in $(seq 1 60); do
              st="$("$P"/psql -h "$SOCK" -p 5433 -d postgres -tAc 'select pg_is_in_recovery()' 2>/dev/null || true)"
              [ "$st" = f ] && break
              sleep 2
            done
            add "recovery terminé (in_recovery=$st)"

            VW="$("$P"/psql -h "$SOCK" -p 5433 -d vaultwarden -tAc 'select count(*) from users' 2>&1 | tr -d '[:space:]')"
            PW="$("$P"/psql -h "$SOCK" -p 5433 -d 'prowlarr-main' -tAc "select count(*) from information_schema.tables where table_schema='public'" 2>&1 | tr -d '[:space:]')"
            add "vaultwarden users: $VW"
            add "prowlarr tables: $PW"

            "$P"/pg_ctl -D "$RDIR" -w stop || true
            rm -rf "$RDIR" "$SOCK"

            [ "$st" = f ] || exit 1
            case "$VW" in "" | *[!0-9]*) exit 1 ;; esac
            case "$PW" in "" | *[!0-9]*) exit 1 ;; esac
          '';
        };

        # 4. Blob-level read-data for the big immich repos (×3: s3/usb/hetzner),
        #    too large for a weekly full read. Each week reads one rotating
        #    slice N/13 (derived from the ISO week), so the whole repo is
        #    re-decrypted over ~13 weeks. Hetzner traffic is free; the cost is
        #    home bandwidth (~1/13 of ~430 GB) + local disk I/O.
        restic-read-data = {
          description = "Weekly rotating read-data verification of big repos (immich)";
          startAt = "Sun 08:00";
          path = [
            pkgs.restic
            pkgs.openssh
          ]
          ++ commonPath;
          serviceConfig = {
            Type = "oneshot";
            EnvironmentFile = config.age.secrets."restic.env".path;
            # Downloads a slice from Hetzner + reads slices from USB — can be long.
            TimeoutStartSec = "6h";
          };
          script = ''
            source ${reportLib}
            TITLE="restic-read-data (slice tournante)"
            SLICES=13
            N=$(( 10#$(date +%V) % SLICES + 1 ))
            add "slice $N/$SLICES (semaine ISO $(date +%V))"
            OK=0; KO=0; FAILED=0
            LOG="$(mktemp)"
            while read -r name repo; do
              [ -z "$name" ] && continue
              if restic -r "$repo" check --read-data-subset="$N/$SLICES" >"$LOG" 2>&1; then
                OK=$((OK + 1)); add "✓ $name"
              else
                KO=$((KO + 1)); FAILED=1
                add "✗ $name"
                add "$(tail -n 3 "$LOG")"
              fi
            done <<'REPOS'
            ${bigRepoLines}
            REPOS
            add "OK: $OK — KO: $KO — couverture complète tous les $SLICES cycles"
            exit $FAILED
          '';
        };
      };
    };
}
