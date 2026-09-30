_: {
  flake.modules.nixos.beets =
    { pkgs, ... }:
    let
      beetsConfig = pkgs.writeText "beets-classique.yaml" ''
        directory: /mnt/storage/medias/musique/classique
        library: /mnt/ultra/beets-classique/library.db

        import:
          copy: yes            # défaut ; `beet import -m` (move) sur les
                               # téléchargements Soulseek, à jeter après import
          write: yes
        per_disc_numbering: yes  # coffrets : la numérotation repart à 1 par disque

        # `musicbrainz` est la source de métadonnées elle-même depuis beets 2.x
        # (défaut du paquet : `plugins: [musicbrainz]`) : notre liste le
        # remplace, donc le retirer couperait l'autotag et priverait
        # `parentwork` de `mb_workid`.
        plugins: musicbrainz parentwork mbsync fetchart scrub replaygain edit

        parentwork:
          auto: yes            # sans ça, champs vides au calcul du chemin
          force: no

        # Le défaut (`command`) exige mp3gain/aacgain — absents du wrapper — et
        # ne couvre pas le FLAC ; ffmpeg est câblé dans le PATH du paquet.
        replaygain:
          backend: ffmpeg
          auto: yes

        paths:
          # L'album reste l'unité sur disque : les formats de chemin sont
          # évalués par item, une arborescence par œuvre éclaterait les
          # récitals et coffrets. La hiérarchie vit dans les tags (Navidrome).
          default: $albumartist/$album%aunique{} ($year)/$track $title
          singleton: Divers/$artist - $title
      '';
    in
    {
      environment.systemPackages = [
        # Découpage image+.cue (M4) : INPUT = dossier ou fichier .cue.
        pkgs.unflac
        # Wrapper dédié : la config est en store (lue par --config), l'état
        # (library.db) vit dans /mnt/ultra/beets-classique. UMask 0002 pour que
        # les imports rejoignent le groupe media, comme ceux de Lidarr.
        (pkgs.writeShellScriptBin "beet-classique" ''
          umask 0002
          exec ${pkgs.beets}/bin/beet --config ${beetsConfig} "$@"
        '')
      ];

      systemd.tmpfiles.rules = [
        "d /mnt/ultra/beets-classique 2775 logikdev media - -"
      ];

      backups.sources.beets = {
        paths = [ "/mnt/ultra/beets-classique" ];
        # Pas d'unité `beets` : le défaut (manageService = true) générerait
        # `systemctl stop beets.service` et ferait échouer le job (restic.nix).
        manageService = false;
      };
    };
}
