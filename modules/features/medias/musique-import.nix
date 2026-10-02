_: {
  flake.modules.nixos.musique-import =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      beet = import ./lib/_beet-classique.nix { inherit pkgs; };
      vpnCfg = config.vpn.airvpn;
      slskdCfg = config.services.slskd;
      downloads = slskdCfg.settings.directories.downloads;
      incomplete = slskdCfg.settings.directories.incomplete;
      queue = "/mnt/storage/medias/downloads/musique-a-importer";
      sources = "/mnt/storage/medias/downloads/musique-sources";
      torrentDir = "/mnt/storage/medias/downloads/classique";
      settle = "15";
      pushNtfy = import ../monitoring/lib/_ntfy.nix { inherit pkgs; };

      # API qBittorrent : `musique add` et les torrents de `liste` n'existent
      # que si le secret (QBT_USER/QBT_PASS) est déployé. Les `if` Nix sont
      # paresseux : sans le secret, la sélection d'attribut n'est jamais évaluée.
      hasMusiqueSecret = builtins.hasAttr "musique.env" config.age.secrets;
      musiqueSecretPath = if hasMusiqueSecret then config.age.secrets."musique.env".path else "";
      # Surcharger `age.secrets."musique.env"` en testant `config.age.secrets`
      # serait une récursion infinie (l'attribut que ce module définit sert à
      # décider de sa propre définition). On sonde donc la source de
      # l'auto-découverte (`secrets.nix`), qui est exactement ce fichier.
      musiqueSecretFile = "${config.secrets.hostsSecretsDir}/${config.networking.hostName}/musique.env.age";
      # Adresse du netns (M11), jamais `10.200.0.2:8090` en dur : le port vient
      # de la config réelle de qBittorrent, l'IP de la veth.
      qbtBase = "http://${config.vpn.airvpn.netns.namespaceAddress}:${toString config.services.qbittorrent.webuiPort}";

      # Marqueur compact d'état qBittorrent (4.x : pausedUP, 5.x : stoppedUP).
      qbtMark = ''
        def mark:
          if . == "uploading" or . == "stalledUP" or . == "forcedUP" or . == "queuedUP" then "↑"
          elif . == "downloading" or . == "stalledDL" or . == "forcedDL" or . == "metaDL" then "↓"
          elif . == "pausedDL" or . == "pausedUP" or . == "stoppedDL" or . == "stoppedUP" then "‖"
          elif . == "error" or . == "missingFiles" then "!"
          elif . == "checkingDL" or . == "checkingUP" or . == "checkingResumeData" or . == "moving" then "…"
          else "?" end;
      '';

      qbtHelpers = lib.optionalString hasMusiqueSecret ''
        qbt_login() {
          # Secret systemd-like : QBT_USER / QBT_PASS. Déjà chargé par
          # l'appelant quand il vient de $CREDENTIALS_DIRECTORY (seul chemin
          # lisible par `musique-prepare`, dont le compte beets ne peut pas lire
          # le secret agenix owner logikdev) ; sinon on source le secret.
          if [ -z "''${QBT_USER:-}" ]; then
            set -a
            # shellcheck source=/dev/null
            . ${musiqueSecretPath}
            set +a
          fi
          # qBittorrent 5.x répond 204 sans corps (l'ancien « Ok. » a disparu) :
          # on valide sur le code HTTP, pas sur le corps.
          code=$(curl -sS -c "$qbtJar" -o /dev/null -w '%{http_code}' \
            --data-urlencode "username=$QBT_USER" \
            --data-urlencode "password=$QBT_PASS" \
            -H "Referer: ${qbtBase}" \
            "${qbtBase}/api/v2/auth/login") || true
          case "$code" in
            2??) return 0 ;;
            *)
              echo "échec de connexion qBittorrent (HTTP $code)" >&2
              return 1
              ;;
          esac
        }
        qbt_get() { curl -sS -b "$qbtJar" "${qbtBase}/api/v2/$1"; }
      '';

      # Section torrents de `liste` : état/ratio/progression de la catégorie
      # `classique`, triés par date d'ajout.
      listeTorrents = lib.optionalString hasMusiqueSecret ''
        qbtJar=$(mktemp)
        trap 'rm -f "$qbtJar"' EXIT
        if qbt_login; then
          printf '\nTéléchargements classique (qBittorrent) :\n'
          qbt_get "torrents/info?category=classique&sort=added_on" \
            | jq -r '${qbtMark}
                if length == 0 then "  (aucun)"
                else .[] | "\(.state | mark) \(.progress * 100 | floor)%  ratio \((((.ratio // 0) * 100) | floor) / 100)  \(.name)"
                end'
        fi
      '';

      # `add` : magnet ou `.torrent` vers qBittorrent, catégorie `classique`.
      # L'entrée arrive TOUJOURS par stdin (le shell ne porte jamais un magnet,
      # et un `.torrent` binaire perdrait ses NUL dans une variable).
      addCommand = lib.optionalString hasMusiqueSecret ''
        add)
          tmp=$(mktemp)
          qbtJar=$(mktemp)
          trap 'rm -f "$tmp" "$qbtJar"' EXIT
          cat > "$tmp"
          [ -s "$tmp" ] || { echo "entrée vide" >&2; exit 2; }

          if grep -q 'viewtopic\.php?t=' "$tmp"; then
            echo "lien de page de forum : copie le lien magnet ou télécharge le .torrent" >&2
            exit 2
          fi

          qbt_login
          # createCategory est idempotent : un 409 « existe déjà » n'est pas une
          # erreur (et curl ne le considère pas comme telle sans `-f`).
          curl -sS -b "$qbtJar" -o /dev/null \
            --data-urlencode "category=classique" \
            --data-urlencode "savePath=/mnt/storage/medias/downloads/classique" \
            "${qbtBase}/api/v2/torrents/createCategory"

          hash=""
          if [ "$(head -c 7 "$tmp")" = "magnet:" ]; then
            hash=$(grep -oiE 'xt=urn:btih:[0-9a-z]+' "$tmp" | head -1 | cut -d: -f3 | tr '[:upper:]' '[:lower:]' || true)
            curl -sS -b "$qbtJar" -o /dev/null \
              --data-urlencode "urls@-" \
              --data-urlencode "category=classique" \
              --data-urlencode "savepath=/mnt/storage/medias/downloads/classique" \
              --data-urlencode "tags=classique" \
              "${qbtBase}/api/v2/torrents/add" < "$tmp"
          else
            curl -sS -b "$qbtJar" -o /dev/null \
              --form "torrents=@$tmp" \
              --form "category=classique" \
              --form "savepath=/mnt/storage/medias/downloads/classique" \
              --form "tags=classique" \
              "${qbtBase}/api/v2/torrents/add"
          fi

          # AutoTMM est désactivé : c'est le savepath posé à l'ajout qui décide
          # (P24). Présence vérifiée par hash si le magnet en porte un, sinon
          # par le torrent le plus récemment ajouté de la catégorie.
          sleep 1
          if [ -n "$hash" ]; then
            torrents=$(qbt_get "torrents/info?hashes=$hash")
          else
            torrents=$(qbt_get "torrents/info?category=classique&sort=added_on&reverse=true")
          fi
          line=$(printf '%s' "$torrents" | jq -r '${qbtMark}
            if length == 0 then empty
            else .[0] | "\(.name) — \(.state | mark) \(.progress * 100 | floor)% · ratio \((((.ratio // 0) * 100) | floor) / 100)"
            end')
          if [ -n "$line" ]; then
            printf 'Ajouté (catégorie classique) : %s\n' "$line"
          else
            printf '%s\n' "envoyé à qBittorrent, pas encore visible — vérifier avec « musique liste »"
          fi
        ;;
      '';

      # Import beets automatique, opt-in (`musique.autoImport`) : la passe
      # prépare puis importe sans attendre le Mac. Désactivé par défaut — le
      # classique s'apparie mal, activer après mesure du taux de match (WP5).
      # Les albums restés en file après la tentative (`skipped`) sont comptés
      # « à corriger » dans la notification ntfy (transition seulement).
      autoImportScript = lib.optionalString config.musique.autoImport ''
        for dir in ${queue}/*/; do
          [ -d "$dir" ] || continue
          [ -z "$(find "$dir" -type f \( -iname '*.flac' -o -iname '*.ape' -o -iname '*.wv' \) -print -quit)" ] && continue
          autoTried=$((autoTried + 1))
          flat=""
          [ -z "$(find "$dir" -maxdepth 1 -type f -iname '*.flac' -print -quit)" ] \
            && [ -n "$(find "$dir" -mindepth 2 -type f -iname '*.flac' -print -quit)" ] && flat="--flat"
          # -i (incrémental) : beets mémorise les dossiers déjà vus/sautés → pas de
          # requêtes MusicBrainz ni de réimport en boucle à chaque passe.
          flock -w 5 "${beet.lock}" "${beet.package}/bin/beet-classique" import -i -q $flat -m "$dir" || true
          if [ -z "$(find "$dir" -type f \( -iname '*.flac' -o -iname '*.ape' -o -iname '*.wv' \) -print -quit)" ]; then
            dest="${sources}/$(basename "$dir")"; [ -e "$dest" ] && dest="$dest-$(date +%s)"
            mv -T "$dir" "$dest"             # résidus seuls : jamais rm
          else
            skipped=$((skipped + 1))         # audio toujours là : à corriger via `musique`
          fi
        done
      '';

      # Passe slskd : SEULS des fichiers récents comptent (un reste abandonné ne
      # fige pas la passe). Un transfert en cours ne reporte QUE cette passe —
      # la passe torrents ci-dessous est indépendante (B3).
      slskdPass = lib.optionalString slskdCfg.enable ''
        do_slskd=1
        if [ -n "$(find ${incomplete} -type f -newermt "-${settle} minutes" -print -quit)" ]; then
          echo "slskd télécharge encore, passe slskd reportée"; do_slskd=0
        fi

        if [ "$do_slskd" -eq 1 ]; then
          for entry in ${downloads}/*/; do
            [ -d "$entry" ] || continue
            name="$(basename "$entry")"
            case "$name" in musique-a-importer|musique-sources) continue ;; esac

            if ( set -e
              album="$entry"
              # slskd peut nicher (pseudo/album) : descendre tant qu'il n'y a pas d'audio direct
              # et un seul sous-dossier.
              while [ -z "$(audio_max1 "$album")" ] && [ "$(find "$album" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ]; do
                album="$(find "$album" -mindepth 1 -maxdepth 1 -type d)"
              done
              name="$(basename "$album")"
              a="$(audio "$album")"; c="$(cues "$album")"
              [ "$a" -gt 0 ] || { echo "ignoré (aucun audio) : $name"; exit 3; }

              tmp="${queue}/.tmp-$name"; rm -rf "$tmp"; mkdir -p "$tmp"
              if [ "$c" -gt 0 ] && [ "$a" -le "$c" ]; then
                # image+.cue : unflac par .cue, sous-dossier dérivé du NOM DU FICHIER .cue
                # (`.Input.Title` est le titre d'album, identique d'un disque à l'autre).
                for cue in "$album"/*.cue; do
                  if [ "$c" -gt 1 ]; then out="$tmp/$(basename "$cue" .cue)"; mkdir -p "$out"; else out="$tmp"; fi
                  unflac -q -o "$out" -n "$tpl" "$cue"
                done
                dest="${sources}/$name"; [ -e "$dest" ] && dest="$dest-$(date +%s)"
                mv -T "$album" "$dest"          # filet, purgé à 14 j par tmpfiles
              else
                # déjà découpé (plate, ou coffret multi-disque en sous-dossiers) : on déplace.
                find "$album" -mindepth 1 -maxdepth 1 -exec mv -t "$tmp" -- {} +
                rmdir "$album"
              fi
              dest="${queue}/$name"; [ -e "$dest" ] && dest="$dest-$(date +%s)"
              mv -T "$tmp" "$dest"
              rmdir -p --ignore-fail-on-non-empty "$(dirname "$album")" 2>/dev/null || true
            ); then
              prepared=$((prepared + 1))
            else
              st=$?
              [ "$st" -eq 3 ] && continue
              echo "échec préparation : $name"; failed=$((failed + 1)); rm -rf "${queue}/.tmp-$name"
            fi
          done
        fi
      '';

      # Passe torrents classique, pilotée par l'API qBittorrent : la complétion
      # est `amount_left == 0` + `completion_on` (settle), jamais `.!qB` ni le
      # mtime (I5). Copie (jamais `mv`) : le seed reste intact ; le marqueur vit
      # dans /var/lib/musique/prepared, hors de l'arbre seedé et de
      # musique-sources (I6), donc jamais purgé avec les sources.
      # Test manuel (pas de framework dans le dépôt) : déposer des fixtures
      # dans ${torrentDir} (plate, image+cue mono, CD1/CD2 + Scans,
      # single-file, dossier déjà préparé, nom avec espaces ou cyrillique),
      # puis `sudo systemctl start musique-prepare` et `musique liste`.
      torrentsPass = lib.optionalString hasMusiqueSecret ''
        torrentDir=${torrentDir}
        qbtJar=$(mktemp)
        trap 'rm -f "$qbtJar"' EXIT
        # Le compte beets ne peut pas lire le secret agenix (owner logikdev
        # 0400) : systemd (root) le dépose dans $CREDENTIALS_DIRECTORY.
        # shellcheck source=/dev/null
        . "$CREDENTIALS_DIRECTORY/musique.env"
        if qbt_login; then
          now=$(date +%s)
          # Process substitution : un pipe perdrait prepared/failed dans un
          # sous-shell.
          while IFS=$'\t' read -r hash cpath; do
            case "$cpath" in
              "$torrentDir"/*) ;;
              *) echo "torrent classique hors ${torrentDir}, ignoré : $cpath"; continue ;;
            esac
            if [ ! -d "$cpath" ]; then
              # Fichier unique : jamais marqué, donc jamais purgé.
              echo "torrent single-file, ignoré (jamais purgé) : $cpath"
              continue
            fi
            mark="/var/lib/musique/prepared/$hash"
            [ -e "$mark" ] && continue
            name="$(basename "$cpath")"
            if ( set -e
              # Détection récursive (CD1/CD2) ; les cue des pochettes sont exclus.
              mapfile -t cueList < <(find "$cpath" -maxdepth 2 -type f -iname '*.cue' \
                -not -ipath '*/Scans/*' -not -ipath '*/Artwork/*' \
                -not -ipath '*/Covers/*' -not -ipath '*/Booklet/*' | sort)
              a="$(audio "$cpath")"; c=''${#cueList[@]}
              tmp="${queue}/.tmp-$name"; rm -rf "$tmp"; mkdir -p "$tmp"
              if [ "$c" -gt 0 ] && [ "$a" -le "$c" ]; then
                # image+.cue : unflac par .cue, sous-dossier dérivé du NOM DU
                # FICHIER .cue (P27) — `.Input.Title` est identique d'un disque
                # à l'autre.
                for cue in "''${cueList[@]}"; do
                  if [ "$c" -gt 1 ]; then out="$tmp/$(basename "$cue" .cue)"; mkdir -p "$out"; else out="$tmp"; fi
                  unflac -q -o "$out" -n "$tpl" "$cue"
                done
              else
                # Déjà découpé : copie intégrale, jamais `mv`.
                cp -a "$cpath"/. "$tmp"/
              fi
              dest="${queue}/$name"; [ -e "$dest" ] && dest="$dest-$(date +%s)"
              mv -T "$tmp" "$dest"
              mkdir -p /var/lib/musique/prepared
              touch "$mark"
            ); then
              prepared=$((prepared + 1))
            else
              echo "échec préparation torrent : $name"; failed=$((failed + 1)); rm -rf "${queue}/.tmp-$name"
            fi
          done < <(qbt_get "torrents/info?category=classique" | jq -r --argjson now "$now" --argjson settle ${settle} '
              .[] | select(.amount_left == 0 and .completion_on > 0 and ($now - .completion_on) >= ($settle * 60))
              | [.hash, .content_path] | @tsv')
        else
          echo "échec de connexion qBittorrent, passe torrents reportée" >&2
          failed=$((failed + 1))
        fi
      '';

      # Reaper « seed puis suppression » : pour chaque torrent classique
      # complété, supprime le seed (`torrents/delete` `deleteFiles=true`) quand
      # le ratio ou l'âge de seed est atteint. Trois gardes avant toute
      # suppression : marqueur de préparation, préfixe de `content_path`, et
      # aucun symlink cross-seed ne résout dedans (B1 ; l'exclusion
      # `blockList` côté cross-seed est la première moitié de la protection).
      # Tourne sur l'hôte et joint qBittorrent par la veth, comme `add`. Le
      # marqueur dit « préparé », pas « importé » : la copie dans la file est
      # la garantie de non-perte (review #5 / Claude I6).
      reaperScript = ''
        # `set +e` en tête : NixOS préfixe `script` d'un `set -e`, et un
        # incident sur un torrent ne doit pas court-circuiter le jugement des
        # suivants (leçon « collecteur », cf. AGENTS.md).
        set +e

        torrentDir=/mnt/storage/medias/downloads/classique
        ratioMax="''${CLASSIQUE_SEED_RATIO:-2.0}"
        maxDays="''${CLASSIQUE_SEED_DAYS:-30}"
        dryRun="''${CLASSIQUE_DRY_RUN:-0}"
        maxDel="''${CLASSIQUE_MAX_DELETIONS:-5}"

        # Un plafond non numérique ne doit pas désarmer la borne : repli.
        num() { case "$1" in "" | *[!0-9]*) echo "$2" ;; *) echo "$1" ;; esac; }
        maxDays=$(num "$maxDays" 30)
        maxDel=$(num "$maxDel" 5)

        qbtJar=$(mktemp)
        crossTargets=$(mktemp)
        trap 'rm -f "$qbtJar" "$crossTargets"' EXIT
        # systemd lit le secret owner logikdev 0400 et le dépose dans
        # $CREDENTIALS_DIRECTORY : QBT_USER/QBT_PASS bruts.
        # shellcheck source=/dev/null
        . "$CREDENTIALS_DIRECTORY/musique.env"
        ${qbtHelpers}
        source ${pushNtfy}
        export NTFY_CLICK="https://navidrome.hyper.logikdev.fr"

        # Cibles canoniques des liens cross-seed, calculées une seule fois. Un
        # lien pointe un fichier de BRANCHE (/mnt/mediasN/medias), pas le pool
        # mergerfs : cross_seed_hit projette content_path dans les deux.
        for dir in /mnt/medias1/cross-seed-links /mnt/medias2/cross-seed-links; do
          [ -d "$dir" ] || continue
          ${pkgs.findutils}/bin/find "$dir" -type l -exec readlink -f -- {} + 2>/dev/null
        done > "$crossTargets"

        cross_seed_hit() {
          local cpath target p
          # readlink -f des deux côtés : si un composant de chemin est un
          # symlink, la comparaison littérale mentirait.
          cpath=$(readlink -f -- "$1" 2>/dev/null) || cpath="$1"
          local rel="''${cpath#/mnt/storage/medias/}"
          local -a prefixes=("$cpath")
          case "$cpath" in
            /mnt/storage/medias/*)
              prefixes+=("/mnt/medias1/medias/$rel" "/mnt/medias2/medias/$rel")
              ;;
          esac
          while IFS= read -r target; do
            for p in "''${prefixes[@]}"; do
              case "$target" in
                "$p" | "$p"/*) return 0 ;;
              esac
            done
          done < "$crossTargets"
          return 1
        }

        if ! qbt_login; then
          echo "échec de connexion qBittorrent, reaper reporté" >&2
          exit 1
        fi

        now=$(date +%s)
        deleted=0
        blocked=0
        failed=0
        blockedMsg=""

        info=$(qbt_get "torrents/info?category=classique") || info=""
        # Seuils en jq (comparaison flottante) : ratio atteint OU âge de seed
        # >= N j ; `completion_on` (item 10), jamais `added_on`. Un torrent
        # complété sans `completion_on` utile (0) n'est pas datable : il reste
        # hors délai et n'est éligible que par le ratio.
        candidates=$(printf '%s' "$info" | jq -r \
          --argjson now "$now" --argjson ratio "$ratioMax" --argjson days "$maxDays" '
            .[] | select(.amount_left == 0 and .completion_on > 0)
            | select((.ratio // 0) >= $ratio
                or ($now - .completion_on) >= ($days * 86400))
            | [.hash, .name, .content_path,
               (((.ratio // 0) * 100 | floor) / 100), .completion_on] | @tsv') \
          || { echo "réponse qBittorrent illisible, reaper reporté" >&2; exit 1; }

        while IFS=$'\t' read -r hash name cpath ratio completion; do
          [ -n "$hash" ] || continue
          # Fichier unique : jamais préparé (donc jamais marqué), et deleteFiles
          # emporterait la copie de bibliothèque hardlinkée : on laisse.
          [ -d "$cpath" ] || { echo "single-file, ignoré (jamais purgé) : $name"; continue; }

          reason=""
          case "$cpath" in
            "$torrentDir"/*) ;;
            *) reason="hors $torrentDir" ;;
          esac
          if [ -z "$reason" ] && [ ! -e "/var/lib/musique/prepared/$hash" ]; then
            reason="sans marqueur"
          fi
          if [ -z "$reason" ] && cross_seed_hit "$cpath"; then
            reason="cross-seed détecté"
          fi
          if [ -n "$reason" ]; then
            echo "seuil atteint, conservé ($reason) : $name"
            blockedMsg="''${blockedMsg}''${name} — $reason"$'\n'
            blocked=$((blocked + 1))
            continue
          fi

          if [ "$deleted" -ge "$maxDel" ]; then
            echo "plafond CLASSIQUE_MAX_DELETIONS=$maxDel atteint, le reste attend la prochaine passe"
            break
          fi

          age=$(( (now - completion) / 86400 ))
          if [ "$dryRun" = "1" ]; then
            echo "dry-run : supprimerait (ratio $ratio, ''${age} j) : $name"
            deleted=$((deleted + 1))
            printf 'DRY-RUN — suppression du seed classique (ratio %s, %s j) : %s' \
              "$ratio" "$age" "$name" \
              | push_ntfy musique "🎼 Musique classique" musical_note low || true
            continue
          fi

          code=$(curl -sS -b "$qbtJar" -o /dev/null -w '%{http_code}' \
            --data-urlencode "hashes=$hash" \
            --data-urlencode "deleteFiles=true" \
            "${qbtBase}/api/v2/torrents/delete") || true
          case "$code" in
            2??)
              deleted=$((deleted + 1))
              echo "supprimé (ratio $ratio, ''${age} j) : $name"
              printf 'Seed purgé (ratio %s, %s j) : %s' "$ratio" "$age" "$name" \
                | push_ntfy musique "🎼 Musique classique" wastebasket low || true
              ;;
            *)
              echo "échec suppression (HTTP $code) : $name" >&2
              failed=$((failed + 1))
              ;;
          esac
        done <<< "$candidates"

        if [ "$blocked" -gt 0 ]; then
          printf 'Seuils atteints sans marqueur / cross-seed détecté :\n%s' "$blockedMsg" \
            | push_ntfy musique "🎼 Musique classique" warning default || true
        fi

        echo "reaper : $deleted purgé(s), $blocked conservé(s), $failed échec(s)"
        [ "$failed" -eq 0 ] || exit 1
        exit 0
      '';
    in
    {
      options.musique.autoImport = lib.mkOption {
        type = lib.types.bool;
        default = false; # activer après mesure du taux de match (cf. §2.3 du plan)
      };

      # Gate : le VPN, pas slskd (I9). La passe torrents classique et
      # `musique-import` existent sans slskd ; seul le parcours slskd reste
      # conditionné à `slskdCfg.enable` (cf. `slskdPass`).
      config = lib.mkIf vpnCfg.enable {
        # `musique-import` tourne sous le compte SSH logikdev : seul lui doit
        # pouvoir lire le secret (QBT_USER/QBT_PASS).
        age.secrets."musique.env" = lib.mkIf (builtins.pathExists musiqueSecretFile) {
          owner = "logikdev";
          mode = "0400";
        };

        users.users.beets = {
          isSystemUser = true;
          group = "media";
        };

        systemd.tmpfiles.rules = [
          "d ${queue} 2775 logikdev media - -"
          # Champ Age AVANT Argument : `d <path> <mode> <user> <group> <age> <arg>`.
          # L'original image+.cue n'est jamais rm par le pipeline : il est purgé
          # ici, à 14 j, quand le split a été validé (et l'import fait).
          "d ${sources} 2775 logikdev media 14d -"
          # Cible de la catégorie qBittorrent `classique` : AutoTMM est off,
          # c'est le savepath posé par `musique add` qui décide (P24).
          "d ${torrentDir} 2775 logikdev media - -"
        ];

        systemd.services.musique-prepare = {
          description = "Découpe et met en file les téléchargements terminés (slskd, torrents classique)";
          unitConfig.RequiresMountsFor = [
            "/mnt/storage"
            "/mnt/ultra"
          ];
          # `path` remplace le PATH ambiant : tout binaire appelé par le script
          # (bash pour les `find -exec sh`, unflac qui wrappe ffmpeg) doit y figurer.
          path = with pkgs; [
            bash
            coreutils
            curl
            findutils
            gnugrep
            jq
            unflac
            util-linux
          ];
          serviceConfig = {
            Type = "oneshot";
            User = "beets";
            UMask = "0002";
            StateDirectory = "musique";
            # Un opéra de 40 pistes = replaygain ffmpeg + fetchart (si autoImport) :
            # borne haute explicite pour qu'un ffmpeg coincé ne fige pas le timer.
            TimeoutStartSec = "6h";
            Nice = 10;
            IOSchedulingClass = "idle";
            # Découpe d'un fichier venu d'un inconnu : jamais sous le compte sudo de l'humain.
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            # ProtectSystem=strict rend tout RO : réouvrir les seuls dossiers
            # écrits (StateDirectory ajoute /var/lib/musique). `downloads` n'est
            # touché que par la passe slskd (mv vers musique-sources) ; la passe
            # torrents ne fait que lire l'arbre seedé (copie, jamais mv).
            ReadWritePaths = [
              queue
              sources
              beet.stateDir
              "/var/log/beets-classique"
            ]
            ++ lib.optionals slskdCfg.enable [ downloads ];
          }
          // lib.optionalAttrs hasMusiqueSecret {
            # Le compte beets ne peut pas lire le secret (owner logikdev 0400) :
            # systemd (root) le lit et l'expose à $CREDENTIALS_DIRECTORY.
            LoadCredential = "musique.env:${musiqueSecretPath}";
          };
          script = ''
            # Fonctions héritées par les sous-shells.
            audio() { find "$1" -type f \( -iname '*.flac' -o -iname '*.ape' -o -iname '*.wv' \) | wc -l; }
            audio_max1() { find "$1" -maxdepth 1 -type f \( -iname '*.flac' -o -iname '*.ape' -o -iname '*.wv' \) -print -quit; }
            cues() { find "$1" -maxdepth 1 -type f -iname '*.cue' | wc -l; }
            tpl='{{printf .Input.TrackNumberFmt .Track.Number}} - {{.Track.Title | Elem}}'
            ${qbtHelpers}

            prepared=0; failed=0; autoTried=0; skipped=0

            ${slskdPass}

            ${torrentsPass}

            ${autoImportScript}

            # File d'attente = dossiers contenant encore de l'audio.
            pending="$(find ${queue} -mindepth 1 -maxdepth 1 -type d ! -name '.tmp-*' \
              -exec sh -c 'find "$1" -type f \( -iname "*.flac" -o -iname "*.ape" -o -iname "*.wv" \) -print -quit | grep -q .' _ {} \; -print | sort)"
            state=/var/lib/musique/pending; prev="$(cat "$state" 2>/dev/null || true)"
            printf '%s\n' "$pending" > "$state"

            if [ "$prepared" -gt 0 ] || [ "$failed" -gt 0 ] || [ "$pending" != "$prev" ]; then
              source ${pushNtfy}
              export NTFY_CLICK="https://navidrome.hyper.logikdev.fr"
              prio=default; [ "$failed" -gt 0 ] && prio=high
              printf '%s' "$prepared préparé(s) (slskd+torrents), $((autoTried - skipped)) importé(s), $skipped à corriger, $failed échec(s) — lancer « musique »." \
                | push_ntfy musique "🎼 Musique classique" musical_note "$prio" || true
            fi
            exit 0
          '';
        };

        systemd.timers.musique-prepare = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "5min";
            OnUnitInactiveSec = "5min";
          };
        };

        # Reaper : host-side, jamais dans le netns. `path` volontairement
        # minimal (`[ curl jq coreutils ]`) ; findutils n'est appelé que par son
        # chemin store pour lister les liens cross-seed.
        systemd.services.classique-reaper = lib.mkIf (vpnCfg.enable && hasMusiqueSecret) {
          description = "Purger les seeds classique préparés (ratio ou délai atteint)";
          unitConfig.RequiresMountsFor = [ "/mnt/storage" ];
          after = [
            "qbittorrent.service"
            "wireguard-wg0.service"
          ];
          wants = [ "qbittorrent.service" ];
          path = with pkgs; [
            curl
            jq
            coreutils
          ];
          serviceConfig = {
            Type = "oneshot";
            # Comme musique-prepare : pas de root. Le secret arrive par
            # LoadCredential (systemd le lit en root) et le marqueur est
            # lisible par beets (groupe media).
            User = "beets";
            TimeoutStartSec = "5min";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            LoadCredential = "musique.env:${musiqueSecretPath}";
            # Défauts visibles (`systemctl show`) et surchargeables par
            # drop-in ; le script garde les mêmes replis pour un test direct.
            Environment = [
              "CLASSIQUE_SEED_RATIO=2.0"
              "CLASSIQUE_SEED_DAYS=30"
              "CLASSIQUE_DRY_RUN=0"
              "CLASSIQUE_MAX_DELETIONS=5"
            ];
          };
          script = reaperScript;
        };

        systemd.timers.classique-reaper = lib.mkIf (vpnCfg.enable && hasMusiqueSecret) {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "10min";
            OnUnitInactiveSec = "10min";
          };
        };

        environment.systemPackages = [
          (pkgs.writeShellApplication {
            name = "musique-import";
            runtimeInputs = with pkgs; [
              coreutils
              curl
              findutils
              fzf
              jq
              systemd
              util-linux
            ];
            text = ''
              usage() { printf 'usage: musique-import [liste|prepare|journal|brut|add]\n'; }
              audio() { find "$1" -type f \( -iname '*.flac' -o -iname '*.ape' -o -iname '*.wv' \) | wc -l; }
              sel() {
                find "${queue}" -mindepth 1 -maxdepth 1 -type d ! -name '.tmp-*' \
                  | fzf --multi --prompt='Album à importer > ' \
                      --preview 'find {} -maxdepth 2 -type f -printf "%P\n" | sort | head -40'
              }
              lock_enter() { exec 9>"${beet.lock}"; flock -n 9 || { echo "import déjà en cours, réessayer"; exit 1; }; }
              imp() {
                local album="$1" flat=()
                if [ "$(find "$album" -maxdepth 1 -type f \( -iname '*.flac' -o -iname '*.ape' -o -iname '*.wv' \) | wc -l)" -eq 0 ] &&
                  [ -n "$(find "$album" -mindepth 2 -type f -iname '*.flac' -print -quit)" ]; then
                  flat=(--flat)
                fi
                ${beet.package}/bin/beet-classique import "''${flat[@]}" -m "$album"
                if [ -z "$(find "$album" -type f \( -iname '*.flac' -o -iname '*.ape' -o -iname '*.wv' \) -print -quit)" ]; then
                  local dest
                  dest="${sources}/$(basename "$album")"; [ -e "$dest" ] && dest="$dest-$(date +%s)"
                  mv -T "$album" "$dest"    # résidus (nfo, jpg) ; jamais rm
                fi
              }

              ${qbtHelpers}

              case "''${1:-}" in
                liste)
                  find "${queue}" -mindepth 1 -maxdepth 1 -type d ! -name '.tmp-*' | sort | while read -r d; do
                    printf '%3s pistes  %6s  %s\n' "$(audio "$d")" "$(du -sh "$d" | cut -f1)" "$(basename "$d")"
                  done
                  ${listeTorrents}
                  echo; tail -n 5 "${beet.log}" 2>/dev/null || true ;;
                prepare)
                  sudo systemctl start --no-block musique-prepare.service
                  journalctl -fu musique-prepare --no-pager ;;
                journal)
                  journalctl -u musique-prepare -n 50 --no-pager ;;
                brut)
                  mapfile -t chosen < <(sel); [ "''${#chosen[@]}" -gt 0 ] || exit 0
                  lock_enter
                  for album in "''${chosen[@]}"; do
                    ${beet.package}/bin/beet-classique import --noautotag -m "$album"
                    ${beet.package}/bin/beet-classique edit   # même verrou : edit écrit la DB
                  done ;;
                ${addCommand}
                ""|import)
                  mapfile -t chosen < <(sel); [ "''${#chosen[@]}" -gt 0 ] || exit 0
                  lock_enter
                  for album in "''${chosen[@]}"; do imp "$album"; done ;;
                *) usage; exit 2 ;;
              esac
            '';
          })
        ];

        # `classique-reaper` n'existe que si le VPN et le secret sont là : son
        # entrée notify doit porter exactement la même condition que l'unité
        # (FAC-5, review #4), sinon le nom référence une unité fantôme.
        notify.services = [
          "musique-prepare"
        ]
        ++ lib.optionals (vpnCfg.enable && hasMusiqueSecret) [ "classique-reaper" ];
      };
    };

  # Commande disponible seulement sur m4 : l'import se fait depuis le Mac,
  # jamais depuis hyper (pas de `ssh hyper` depuis hyper).
  flake.modules.homeManager.musique =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellScriptBin "musique" ''
          # `add` transfère stdin en binaire : surtout pas de `-t`, un TTY
          # corromprait le `.torrent`/le magnet. Les autres sous-commandes
          # gardent le TTY (fzf, `journalctl -f`).
          case "''${1:-}" in
            add)
              case "''${2:-}" in
                "")
                  "/usr/bin/pbpaste" | ssh hyper -- musique-import add - ;;
                *)
                  if [ -f "$2" ]; then
                    ssh hyper -- musique-import add - < "$2"
                  else
                    printf '%s' "$2" | ssh hyper -- musique-import add -
                  fi ;;
              esac
              exit $? ;;
          esac
          exec ssh -t hyper -- musique-import "$@"
        '')
      ];
    };
}
