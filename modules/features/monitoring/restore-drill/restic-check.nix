{ ... }:
let
  resticCheckModule =
    {
      pkgs,
      config,
      ...
    }:
    let
      inherit (config.restoreDrill.lib) reportLib commonPath repoLines;
    in
    {
      systemd.services.restic-check = {
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
    };
in
{
  flake.modules.nixos.restoreDrill.imports = [ resticCheckModule ];
}
