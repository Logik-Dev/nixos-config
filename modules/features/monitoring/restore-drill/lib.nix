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
      # (rustfs used to be here too, until the wholesale rustfs-usb backup and
      # then rustfs itself were dropped — see docs/backups.md.)
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
      options.restoreDrill.lib = lib.mkOption {
        type = lib.types.attrsOf lib.types.unspecified;
        default = { };
      };

      config = {
        restoreDrill.lib = {
          inherit
            reportLib
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
