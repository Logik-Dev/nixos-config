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

      notify.services = [ "podman-lidarr-metadata" ];

      # Lidarr n'expose pas metadataSource dans son UI — c'est un réglage en
      # base (IConfigService), pas dans config.xml, donc aucun override
      # d'environnement n'existe. La bascule est de l'état impératif.
      #
      # Le service ne fait AUCUNE attente : il tente une fois, échoue vite si
      # Lidarr (Type=simple : actif avant que l'API écoute) ou le provider ne
      # sont pas prêts, et le timer le relance. `RemainAfterExit` garde le
      # service actif après succès, ce qui désarme le timer : la bascule
      # idempotente ne se rejoue plus (hors reboot).
      systemd.services.lidarr-metadata-switch = {
        description = "Point Lidarr at the self-hosted metadata provider";
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

          test -f "$cfg" || { echo "config.xml pas encore écrit par Lidarr"; exit 1; }

          key=$(sed -n 's:.*<ApiKey>\([^<]*\)</ApiKey>.*:\1:p' "$cfg" | head -1)
          [ -n "$key" ] || { echo "clé API introuvable dans $cfg"; exit 1; }

          current=$(curl -fsS --max-time 10 -H "X-Api-Key: $key" "$api") \
            || { echo "API Lidarr injoignable"; exit 1; }

          current_source=$(printf '%s' "$current" | jq -r '.metadataSource // ""')
          if [ "$current_source" = "${target}" ]; then
            echo "metadataSource déjà positionné sur ${target}"
            exit 0
          fi

          # Ne bascule que si le provider répond : sinon on laisserait Lidarr
          # sur un metadataSource injoignable si le conteneur est en échec.
          curl -fsS --max-time 5 "http://127.0.0.1:${toString port}/healthz" >/dev/null \
            || { echo "metadata-provider pas prêt (healthz KO)"; exit 1; }

          updated=$(printf '%s' "$current" | jq --arg src "${target}" '.metadataSource = $src')
          curl -fsS --max-time 30 -X PUT -H "X-Api-Key: $key" -H "Content-Type: application/json" \
            -d "$updated" "$api" >/dev/null || { echo "PUT refusé par Lidarr"; exit 1; }

          verify=$(curl -fsS --max-time 10 -H "X-Api-Key: $key" "$api" | jq -r '.metadataSource // ""')
          [ "$verify" = "${target}" ] || {
            echo "la bascule n'a pas pris (metadataSource=$verify)"
            exit 1
          }
          echo "Lidarr pointe sur ${target}"
        '';
      };

      systemd.timers.lidarr-metadata-switch = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitInactiveSec = "5min";
        };
      };
    };
}
