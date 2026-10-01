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
      slskdCfg = config.services.slskd;
      downloads = slskdCfg.settings.directories.downloads;
      incomplete = slskdCfg.settings.directories.incomplete;
      queue = "/mnt/storage/medias/downloads/musique-a-importer";
      sources = "/mnt/storage/medias/downloads/musique-sources";
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
          # Secret systemd-like : QBT_USER / QBT_PASS.
          set -a
          # shellcheck source=/dev/null
          . ${musiqueSecretPath}
          set +a
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
      autoImportScript = lib.optionalString config.musique.autoImport ''
        for dir in ${queue}/*/; do
          [ -d "$dir" ] || continue
          [ -z "$(find "$dir" -type f \( -iname '*.flac' -o -iname '*.ape' -o -iname '*.wv' \) -print -quit)" ] && continue
          flat=""
          [ -z "$(find "$dir" -maxdepth 1 -type f -iname '*.flac' -print -quit)" ] \
            && [ -n "$(find "$dir" -mindepth 2 -type f -iname '*.flac' -print -quit)" ] && flat="--flat"
          # -i (incrémental) : beets mémorise les dossiers déjà vus/sautés → pas de
          # requêtes MusicBrainz ni de réimport en boucle à chaque passe.
          flock -w 5 "${beet.lock}" "${beet.package}/bin/beet-classique" import -i -q $flat -m "$dir" || true
          if [ -z "$(find "$dir" -type f \( -iname '*.flac' -o -iname '*.ape' -o -iname '*.wv' \) -print -quit)" ]; then
            dest="${sources}/$(basename "$dir")"; [ -e "$dest" ] && dest="$dest-$(date +%s)"
            mv -T "$dir" "$dest"             # résidus seuls : jamais rm
          fi
        done
      '';
    in
    {
      options.musique.autoImport = lib.mkOption {
        type = lib.types.bool;
        default = false; # activer après mesure du taux de match (cf. §2.3 du plan)
      };

      config = lib.mkIf slskdCfg.enable {
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
          "d /mnt/storage/medias/downloads/classique 2775 logikdev media - -"
        ];

        systemd.services.musique-prepare = {
          description = "Découpe et met en file les téléchargements slskd terminés";
          unitConfig.RequiresMountsFor = [
            "/mnt/storage"
            "/mnt/ultra"
          ];
          # `path` remplace le PATH ambiant : tout binaire appelé par le script
          # (bash pour les `find -exec sh`, unflac qui wrappe ffmpeg) doit y figurer.
          path = with pkgs; [
            bash
            coreutils
            findutils
            gnugrep
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
            # écrits (StateDirectory ajoute /var/lib/musique).
            ReadWritePaths = [
              downloads
              queue
              sources
              beet.stateDir
              "/var/log/beets-classique"
            ];
          };
          script = ''
            # Fonctions héritées par les sous-shells.
            audio() { find "$1" -type f \( -iname '*.flac' -o -iname '*.ape' -o -iname '*.wv' \) | wc -l; }
            audio_max1() { find "$1" -maxdepth 1 -type f \( -iname '*.flac' -o -iname '*.ape' -o -iname '*.wv' \) -print -quit; }
            cues() { find "$1" -maxdepth 1 -type f -iname '*.cue' | wc -l; }
            tpl='{{printf .Input.TrackNumberFmt .Track.Number}} - {{.Track.Title | Elem}}'

            # Gate slskd : SEULS des fichiers récents comptent (un reste abandonné ne fige pas la passe).
            if [ -n "$(find ${incomplete} -type f -newermt "-${settle} minutes" -print -quit)" ]; then
              echo "slskd télécharge encore, passe reportée"; exit 0
            fi

            prepared=0; failed=0
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

            ${autoImportScript}

            # File d'attente = dossiers contenant encore de l'audio.
            pending="$(find ${queue} -mindepth 1 -maxdepth 1 -type d ! -name '.tmp-*' \
              -exec sh -c 'find "$1" -type f \( -iname "*.flac" -o -iname "*.ape" -o -iname "*.wv" \) -print -quit | grep -q .' _ {} \; -print | sort)"
            count="$(printf '%s\n' "$pending" | grep -c . || true)"
            state=/var/lib/musique/pending; prev="$(cat "$state" 2>/dev/null || true)"
            printf '%s\n' "$pending" > "$state"

            if [ "$prepared" -gt 0 ] || [ "$failed" -gt 0 ] || [ "$pending" != "$prev" ]; then
              source ${pushNtfy}
              export NTFY_CLICK="https://navidrome.hyper.logikdev.fr"
              prio=default; [ "$failed" -gt 0 ] && prio=high
              printf '%s' "$prepared préparé(s), $count en attente, $failed échec(s) — lancer « musique »." \
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

        notify.services = [ "musique-prepare" ];
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
