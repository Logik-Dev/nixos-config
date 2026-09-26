{ ... }:
let
  libModule =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      # One line per (source × repository), space-separated: "<name> <repo> <mode>".
      # immich (~440 GB) is too large for a weekly full --read-data. In the
      # weekly restic-check it gets a structural `restic check` only; its
      # blob-level verification is done incrementally by restic-read-data below
      # (a rotating slice). Everything else is small, so full --read-data is cheap.
      bigSources = [
        "immich"
      ];
      resticRepos = lib.flatten (
        lib.mapAttrsToList (
          sourceName: _sourceValue:
          lib.mapAttrsToList (targetName: repository: {
            name = "${sourceName}-${targetName}";
            inherit repository;
            mode = if lib.elem sourceName bigSources then "struct" else "full";
          }) config.backups.repositories.${sourceName}
        ) config.backups.repositories
      );
      repoLines = lib.concatMapStringsSep "\n" (r: "${r.name} ${r.repository} ${r.mode}") resticRepos;

      # The big repos, for restic-read-data's rotating slice check.
      bigRepoLines = lib.concatMapStringsSep "\n" (r: "${r.name} ${r.repository}") (
        lib.filter (r: r.mode == "struct") resticRepos
      );

      pushNtfy = import ../lib/_ntfy.nix { inherit pkgs; };

      # Sourced by every drill: accumulates a human-readable body with add(),
      # then posts ONE formatted message to the dedicated backup-verify topic on
      # exit — success (✅) and failure (❌) alike, so the weekly run doubles as a
      # heartbeat (silence means the timer itself didn't fire).
      reportLib = pkgs.writeText "backup-verify-report.sh" ''
        source ${pushNtfy}
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
          printf '%s\n\n%s' "$head" "$BODY" | push_ntfy backup-verify "Backup verify" "$tags" "$prio"
        }
        trap _finish EXIT
        set -Eeuo pipefail
      '';

      # Each drill stamps its last run into the node-exporter textfile dir via
      # an ExecStopPost prefixed with "+" (full privileges, so the postgres
      # drill can write too). DrillStale alerts when a stamp goes missing for
      # 9 days — that is the dead-man switch for a timer that stopped firing.
      drillStamp = pkgs.writeShellScript "drill-stamp" ''
        set -eu
        name="$1"
        dir=/var/lib/node-exporter-textfile
        mkdir -p "$dir"
        umask 022
        tmp="$dir/.drill-$name.prom.tmp"
        printf 'drill_last_run_timestamp_seconds{drill="%s"} %s\n' "$name" "$(date +%s)" > "$tmp"
        mv -f "$tmp" "$dir/drill-$name.prom"
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
      options.restoreDrill.lib = lib.mkOption {
        type = lib.types.attrsOf lib.types.unspecified;
        default = { };
      };

      config = {
        restoreDrill.lib = {
          inherit
            reportLib
            drillStamp
            commonPath
            repoLines
            bigRepoLines
            ;
        };

        # postgres-restore-drill runs as the postgres user; give it a writable base.
        systemd.tmpfiles.rules = [ "d /mnt/ultra/restore-test 0700 postgres postgres -" ];
      };
    };
in
{
  flake.modules.nixos.restoreDrill.imports = [ libModule ];
}
