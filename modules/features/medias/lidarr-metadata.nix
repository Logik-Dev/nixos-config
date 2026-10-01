_: {
  flake.modules.nixos.lidarr-metadata =
    {
      config,
      pkgs,
      ...
    }:
    let
      dataDir = "/mnt/ultra/lidarr-metadata";
      port = 5001;
      # Lidarr appends /{route} to metadataSource : le slash final est requis.
      target = "http://localhost:${toString port}/";
    in
    {
      # Serveur de métadonnées auto-hébergé (dataset construit depuis les dumps
      # CC0 MusicBrainz, publication amont 2×/semaine). Réseau hôte : Lidarr le
      # joint en loopback ; le pare-feu de l'hôte garde 5001 fermé sur le LAN.
      virtualisation.oci-containers.containers.lidarr-metadata = {
        image = "ghcr.io/nc1107/lidarr-metadata-provider:latest";
        autoStart = true;
        extraOptions = [ "--network=host" ];
        volumes = [ "${dataDir}:/data" ];
        environment = {
          LMP_DATASET_URL = "https://github.com/NC1107/lidarr-metadata-provider/releases/latest/download/dataset.db";
          # Opt-in : vérifie une nouvelle version toutes les 72 h et bascule à
          # chaud (~8 Go par mise à jour, deux copies pendant le swap).
          LMP_DATASET_REFRESH = "72h";
          # Repli live MusicBrainz pour ce qui est plus récent que le dataset.
          # -contact est exigé par MusicBrainz dès que -fallback est actif.
          LMP_FALLBACK = "true";
          LMP_CONTACT = config.constants.users.logikdev.email;
        };
      };

      systemd.tmpfiles.rules = [
        # L'image tourne en uid 1000 (logikdev), comme les autres services média.
        "d ${dataDir} 2755 logikdev media - -"
      ];

      # La bascule est surveillée elle aussi : si elle échoue durablement (clé
      # API illisible, provider en échec), Lidarr **reste sur le provider
      # cloud** — exactement ce que ce module veut éviter, et sans ça rien ne le
      # dirait. Le prix est au pire une notification par démarrage, quand Lidarr
      # n'écoute pas encore au premier essai (d'où OnBootSec à 5 min).
      notify.services = [
        "podman-lidarr-metadata"
        "lidarr-metadata-switch"
      ];

      # Lidarr n'expose ni metadataSource ni writeAudioTags dans config.xml —
      # ce sont des réglages en base (IConfigService), donc aucun override
      # d'environnement n'existe. Les deux sont de l'état impératif, et c'est
      # le même appel API qui les porte.
      #
      # `writeAudioTags = allFiles` (« All files; initial import only ») +
      # `embedCoverArt` : sans ça, les fichiers importés gardent les tags du
      # torrent (ALBUMARTIST absent ou fautif → Navidrome éclate un album par
      # artiste de piste) et n'ont aucune pochette embarquée (Navidrome ne
      # télécharge jamais d'image). Corollaire assumé : l'écriture des tags se
      # fait sur le fichier hardlinké, donc le hash du torrent correspondant
      # devient invalide (Lidarr #1016) — voir P32.
      #
      # Le service ne fait AUCUNE attente : il tente une fois, échoue vite si
      # Lidarr (Type=simple : actif avant que l'API écoute) ou le provider ne
      # sont pas prêts, et le timer le relance. `RemainAfterExit` garde le
      # service actif après succès, ce qui désarme le timer : la bascule
      # idempotente ne se rejoue plus (hors reboot).
      systemd.services.lidarr-metadata-switch = {
        description = "Pin Lidarr metadata source, tag writing and cover embedding";
        after = [
          "lidarr.service"
          "podman-lidarr-metadata.service"
        ];
        unitConfig.RequiresMountsFor = [ "/mnt/ultra" ];
        path = with pkgs; [
          coreutils
          curl
          gnused
          jq
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          cfg=/mnt/ultra/lidarr/config.xml
          api="http://127.0.0.1:8686/api/v1/config/metadataprovider"
          tags="allFiles"

          test -f "$cfg" || { echo "config.xml pas encore écrit par Lidarr"; exit 1; }

          key=$(sed -n 's:.*<ApiKey>\([^<]*\)</ApiKey>.*:\1:p' "$cfg" | head -1)
          [ -n "$key" ] || { echo "clé API introuvable dans $cfg"; exit 1; }

          current=$(curl -fsS --max-time 10 -H "X-Api-Key: $key" "$api") \
            || { echo "API Lidarr injoignable"; exit 1; }

          cur_source=$(printf '%s' "$current" | jq -r '.metadataSource // ""')
          cur_tags=$(printf '%s' "$current" | jq -r '.writeAudioTags // ""')
          cur_embed=$(printf '%s' "$current" | jq -r '.embedCoverArt // false')

          if [ "$cur_source" = "${target}" ] && [ "$cur_tags" = "$tags" ] && [ "$cur_embed" = "true" ]; then
            echo "config metadata déjà conforme (source, writeAudioTags, embedCoverArt)"
            exit 0
          fi

          # Ne bascule la source que si le provider répond : sinon on laisserait
          # Lidarr sur un metadataSource injoignable si le conteneur est en échec.
          # Les autres réglages n'en dépendent pas.
          if [ "$cur_source" != "${target}" ]; then
            curl -fsS --max-time 5 "http://127.0.0.1:${toString port}/healthz" >/dev/null \
              || { echo "metadata-provider pas prêt (healthz KO)"; exit 1; }
          fi

          updated=$(printf '%s' "$current" | jq --arg src "${target}" --arg tags "$tags" \
            '.metadataSource = $src | .writeAudioTags = $tags | .embedCoverArt = true')
          curl -fsS --max-time 30 -X PUT -H "X-Api-Key: $key" -H "Content-Type: application/json" \
            -d "$updated" "$api" >/dev/null || { echo "PUT refusé par Lidarr"; exit 1; }

          verify=$(curl -fsS --max-time 10 -H "X-Api-Key: $key" "$api")
          v_source=$(printf '%s' "$verify" | jq -r '.metadataSource // ""')
          v_tags=$(printf '%s' "$verify" | jq -r '.writeAudioTags // ""')
          v_embed=$(printf '%s' "$verify" | jq -r '.embedCoverArt // false')
          if [ "$v_source" = "${target}" ] && [ "$v_tags" = "$tags" ] && [ "$v_embed" = "true" ]; then
            echo "Lidarr : source=${target}, writeAudioTags=$tags, embedCoverArt=true"
          else
            echo "la config n'a pas pris (source=$v_source tags=$v_tags embed=$v_embed)"
            exit 1
          fi
        '';
      };

      systemd.timers.lidarr-metadata-switch = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5min";
          OnUnitInactiveSec = "5min";
        };
      };
    };
}
