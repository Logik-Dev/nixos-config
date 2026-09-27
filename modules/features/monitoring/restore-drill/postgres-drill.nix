_:
let
  postgresDrillModule =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      inherit (config.restoreDrill.lib) reportLib drillStamp commonPath;
      pg = config.services.postgresql.finalPackage;
    in
    {
      systemd.services.postgres-restore-drill = {
        description = "Weekly postgres restore drill (pgBackRest ← Hetzner → throwaway instance)";
        startAt = "Sun 11:00";
        path = [ pkgs.jq ] ++ commonPath;
        unitConfig.RequiresMountsFor = [ "/mnt/ultra" ];
        serviceConfig = {
          Type = "oneshot";
          User = "postgres";
          Group = "postgres";
          EnvironmentFile = config.age.secrets."pgbackrest.env".path;
          TimeoutStartSec = "45min";
          ExecStopPost = [ "+${drillStamp} postgres-restore-drill" ];
        };
        script = ''
          source ${reportLib}
          TITLE="postgres-restore-drill (pgBackRest ← Hetzner)"
          P=${pg}/bin
          PGB=${lib.getExe pkgs.pgbackrest}
          ROOT=/mnt/ultra/restore-test; RDIR=$ROOT/pg; SOCK=$ROOT/sock
          rm -rf "$RDIR" "$SOCK"; mkdir -p "$RDIR" "$SOCK"; chmod 700 "$RDIR"

          # The restore only proves the chain works; it says nothing about the
          # backup's age. Fail on a full older than 9 days.
          LAST="$("$PGB" --stanza=default info --output=json | ${lib.getExe pkgs.jq} -r \
            '[.[] | .backup[]? | select(.type=="full" and (.error|not)) | .timestamp.stop] | max')"
          case "$LAST" in "" | null | *[!0-9]*) add "aucun full trouvé dans pgbackrest info"; exit 1 ;; esac
          AGE=$(( $(date +%s) - LAST ))
          add "dernier full: il y a $(( AGE / 86400 )) j"
          [ "$AGE" -lt 777600 ] || { add "full trop vieux (> 9 j)"; exit 1; }

          "$PGB" --stanza=default check
          add "pgbackrest check ✓"

          "$PGB" --stanza=default --repo=2 restore --pg1-path="$RDIR" \
            --type=immediate --target-action=promote --archive-mode=off
          add "restore complet depuis repo2 (Hetzner) ✓"

          printf "port = 5433\nunix_socket_directories = '%s'\n" "$SOCK" >> "$RDIR/postgresql.auto.conf"

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
    };
in
{
  flake.modules.nixos.restoreDrill.imports = [ postgresDrillModule ];
}
