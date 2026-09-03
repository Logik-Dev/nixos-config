{ ... }:
let
  readDataModule =
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
        bigRepoLines
        ;
    in
    {
      systemd.services.restic-read-data = {
        description = "Weekly rotating read-data verification of big repos (immich)";
        startAt = "Sun 12:00";
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
          CacheDirectory = "restic-read-data";
          Environment = [ "RESTIC_CACHE_DIR=/var/cache/restic-read-data" ];
          ExecStopPost = [ "+${drillStamp} restic-read-data" ];
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
            if restic -r "$repo" check --read-data-subset="$N/$SLICES" --retry-lock 30m >"$LOG" 2>&1; then
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
in
{
  flake.modules.nixos.restoreDrill.imports = [ readDataModule ];
}
