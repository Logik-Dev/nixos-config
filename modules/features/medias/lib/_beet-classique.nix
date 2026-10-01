{ pkgs }:
let
  stateDir = "/mnt/ultra/beets-classique";
  library = "${stateDir}/library.db";
  # Hors de `backups.sources.beets` : un log qui grossit à chaque import
  # gonflerait chaque snapshot restic.
  log = "/var/log/beets-classique/import.log";
  # SQLite : un import auto et un import interactif en parallèle donnent
  # `database is locked`. Les deux appelants prennent ce verrou.
  lock = "${stateDir}/.import.lock";

  config = pkgs.writeText "beets-classique.yaml" ''
    directory: /mnt/storage/medias/musique/classique
    library: ${library}

    import:
      copy: yes
      write: yes
      quiet_fallback: skip      # défaut explicité : en -q, pas de match fort => skip
      duplicate_action: skip
      log: ${log}
    per_disc_numbering: yes

    plugins: musicbrainz parentwork mbsync fetchart scrub replaygain edit

    parentwork:
      auto: yes
      force: no

    # Le wrapper nixpkgs câble les trois binaires (ffmpeg, mp3gain, aacgain),
    # donc le défaut `command` fonctionnerait — mais mp3gain/aacgain ne
    # traitent que MP3/AAC : en classique tout est FLAC, d'où le backend
    # ffmpeg.
    replaygain:
      backend: ffmpeg
      auto: yes

    paths:
      default: $albumartist/$album%aunique{} ($year)/$track $title
      singleton: Divers/$artist - $title
  '';

  package = pkgs.writeShellScriptBin "beet-classique" ''
    umask 0002
    exec ${pkgs.beets}/bin/beet --config ${config} "$@"
  '';
in
{
  inherit
    config
    package
    library
    log
    lock
    stateDir
    ;
}
