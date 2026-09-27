_:
let
  resticCheckModule =
    {
      pkgs,
      config,
      ...
    }:
    let
      inherit (config.restoreDrill.lib)
        reportLib
        drillStamp
        commonPath
        repoLines
        ;
    in
    {
      systemd.services.restic-check = {
        description = "Weekly integrity check of all restic repositories";
        # 09:00: after the 02:05-07:05 backup window and the 01:30 pg_dumpall.
        startAt = "Sun 09:00";
        path = [
          pkgs.restic
          pkgs.openssh
        ]
        ++ commonPath;
        serviceConfig = {
          Type = "oneshot";
          EnvironmentFile = config.age.secrets."restic.env".path;
          CacheDirectory = "restic-check";
          Environment = [ "RESTIC_CACHE_DIR=/var/cache/restic-check" ];
          ExecStopPost = [ "+${drillStamp} restic-check" ];
        };
        script = ''
          source ${reportLib}
          TITLE="restic-check"
          OK=0; KO=0; FAILED=0
          LOG="$(mktemp)"
          while read -r name repo mode; do
            [ -z "$name" ] && continue
            if [ "$mode" = full ]; then args="check --read-data --retry-lock 30m"; else args="check --retry-lock 30m"; fi
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
    };
in
{
  flake.modules.nixos.restoreDrill.imports = [ resticCheckModule ];
}
