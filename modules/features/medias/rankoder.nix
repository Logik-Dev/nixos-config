{ inputs, ... }: {
  flake.modules.nixos.rankoder = { config, ... }: {
    imports = [ inputs.rankoder.nixosModules.default ];

    systemd.tmpfiles.rules = [
      # Parent owned by logikdev (same owner as /mnt/storage/medias) so
      # systemd-tmpfiles can descend into it to create the rankoder-owned
      # subdirs below; a logikdev -> rankoder ownership change here is rejected
      # as an "unsafe path transition". rankoder traverses via the media group.
      "d /mnt/storage/medias/rankoder 0750 logikdev media - -"
      "d /mnt/storage/medias/rankoder/retention 0750 rankoder media - -"
      "d /mnt/storage/medias/rankoder/temp 0750 rankoder media - -"
    ];

    traefik.services.rankoder = {
      port = 8765;
      enableAuthelia = true;
      category = "Médias";
      icon = "di:rankoder";
    };

    notify.services = [ "rankoder" ];

    # Les entités Home Assistant de rankoder, à côté du service qui les alimente.
    # rankoder publie son état sur `rankoder/status` et ses demandes
    # d'approbation sur `rankoder/approval/request` ; sans ce qui suit, il
    # publie dans le vide.
    #
    # Repris du `/config` de l'ancienne VM HAOS, avec trois corrections — voir
    # docs/home-assistant-nix-plan.md §11 pour le détail des défauts trouvés.
    services.home-assistant.config.mqtt.sensor =
      let
        # Les huit capteurs lisent le même message rétenu et n'en extraient
        # qu'un champ : le gabarit évite huit répétitions du topic.
        statusSensor = name: unique_id: icon: template: {
          inherit name unique_id icon;
          state_topic = "rankoder/status";
          value_template = template;
        };
      in
      [
        (statusSensor "rankoder version" "rankoder_version" "mdi:tag" "{{ value_json.version }}")
        (statusSensor "rankoder done" "rankoder_done" "mdi:check-circle" "{{ value_json.done }}")
        (statusSensor "rankoder failed" "rankoder_failed" "mdi:alert-circle" "{{ value_json.failed }}")
        (statusSensor "rankoder transcoding" "rankoder_transcoding" "mdi:cog" "{{ value_json.transcoding }}")
        (statusSensor "rankoder pending approval" "rankoder_pending_approval" "mdi:account-clock" "{{ value_json.pending_approval }}")
        (statusSensor "rankoder skipped" "rankoder_skipped" "mdi:debug-step-over" "{{ value_json.skipped }}")
        {
          name = "rankoder space saved";
          unique_id = "rankoder_space_saved";
          state_topic = "rankoder/status";
          value_template = "{{ value_json.space_saved_gb | round(1) }}";
          unit_of_measurement = "GB";
          device_class = "data_size";
          state_class = "total_increasing";
        }
        {
          name = "rankoder last failure";
          unique_id = "rankoder_last_failure";
          state_topic = "rankoder/status";
          value_template = "{{ value_json.last_failure.title if value_json.last_failure else 'none' }}";
          json_attributes_topic = "rankoder/status";
          json_attributes_template = "{{ value_json.last_failure | tojson }}";
        }
      ];

    homeAssistant.automations = {
      # rankoder demande l'aval avant de transcoder : notification actionnable
      # sur le téléphone, dont les deux boutons encodent le batch_id.
      rankoder_approval_request = {
        alias = "Rankoder — réception demande d'approbation";
        triggers = [
          {
            trigger = "mqtt";
            topic = "rankoder/approval/request";
          }
        ];
        actions = [
          {
            variables = {
              batch_id = "{{ trigger.payload_json.batch_id }}";
              titre = "{{ trigger.payload_json.title }}";
              fichiers = "{{ trigger.payload_json.file_count }}";
              taille = "{{ trigger.payload_json.total_size_gb | round(1) }}";
              gain = "{{ trigger.payload_json.total_space_saved_gb | round(1) }}";
              note = "{{ trigger.payload_json.tmdb_rating }}";
            };
          }
          {
            action = "notify.mobile_app_iphone_de_cedric";
            data = {
              title = "rankoder : transcoder « {{ titre }} » ?";
              message = "{{ fichiers }} fichier(s) · {{ taille }} Go → gain ~{{ gain }} Go{% if note %} · TMDB {{ note }}{% endif %}";
              data = {
                tag = "rankoder_{{ batch_id }}";
                actions = [
                  {
                    action = "RANKODER_APPROVE|{{ batch_id }}";
                    title = "✅ Approuver";
                  }
                  {
                    action = "RANKODER_SKIP|{{ batch_id }}";
                    title = "🚫 Ignorer";
                  }
                ];
              };
            };
          }
        ];
        mode = "parallel";
        max = 10;
      };

      # Le retour du téléphone : republie la décision vers rankoder et efface la
      # notification. Corrigé au passage — la VM ciblait `notify.iphone_de_cedric`
      # pour l'effacement, sans le préfixe `mobile_app_` utilisé partout ailleurs.
      rankoder_approval_response = {
        alias = "Rankoder — traitement de la réponse";
        triggers = [
          {
            trigger = "event";
            event_type = "mobile_app_notification_action";
          }
        ];
        conditions = [
          "{{ trigger.event.data.action is string and trigger.event.data.action.startswith('RANKODER_') }}"
        ];
        actions = [
          {
            variables = {
              parts = "{{ trigger.event.data.action.split('|') }}";
              decision = "{{ parts[0] }}";
              batch_id = "{{ parts[1] }}";
            };
          }
          {
            action = "mqtt.publish";
            data = {
              topic = "rankoder/approval/response";
              qos = 1;
              payload = "{{ {\"batch_id\": batch_id, \"approved\": decision == \"RANKODER_APPROVE\"} | to_json }}";
            };
          }
          {
            action = "notify.mobile_app_iphone_de_cedric";
            data = {
              message = "clear_notification";
              data.tag = "rankoder_{{ batch_id }}";
            };
          }
        ];
        mode = "parallel";
        max = 10;
      };

      # Corrigé : la VM imbriquait le topic sous une clé `options`, que le schéma
      # du déclencheur MQTT ne connaît pas. `topic` étant obligatoire, la
      # configuration était invalide et l'automatisation ne pouvait pas charger —
      # les échecs de transcodage étaient donc silencieux.
      rankoder_transcode_failure = {
        alias = "Rankoder — échec de transcodage";
        triggers = [
          {
            trigger = "mqtt";
            topic = "rankoder/failure";
          }
        ];
        actions = [
          {
            action = "notify.mobile_app_iphone_de_cedric";
            data = {
              title = "Rankoder : transcodage échoué";
              message = "{{ trigger.payload_json.title or trigger.payload_json.media_file_id }} ({{ trigger.payload_json.kind }}) — {{ trigger.payload_json.reason }}";
            };
          }
        ];
        mode = "queued";
        max = 100;
      };

      # NON REPRIS : `rankoder_deliver_deferred` (remise différée à 09:00) et le
      # script qui l'accompagnait. Tous deux conditionnés sur
      # `input_text.rankoder_pending_id`, que **rien n'écrivait** — ni une
      # automatisation, ni un script, ni configuration.yaml. Le mécanisme ne
      # pouvait pas se déclencher. À réimplémenter proprement si le besoin
      # d'une remise différée existe encore.
    };

    # App state/logs only — NOT retentionDir (originals live under
    # /mnt/storage/medias, huge and not meant to be duplicated here).
    backups.sources.rankoder = {
      paths = [ "/var/lib/rankoder" ];
    };

    services.rankoder = {
      enable = true;
      group = "media";
      environmentFile = config.age.secrets."rankoder.env".path;
      jellyfinUrl = "https://jellyfin.hyper.logikdev.fr";
      radarrUrl = "https://radarr.hyper.logikdev.fr";
      sonarrUrl = "https://sonarr.hyper.logikdev.fr";
      mediaPaths = [ "/mnt/storage/medias" ];
      tmpDir = "/mnt/storage/medias/rankoder/temp";
      retentionDir = "/mnt/storage/medias/rankoder/retention";
      minVmaf = 92.0;
      hardwareAcceleration = true;
      mqtt.username = "homeassistant";
      http = {
        enable = true;
        # The UI has no auth of its own — Traefik/Authelia is the only entry
        # point (upstream module explicitly recommends loopback).
        address = "127.0.0.1";
      };
    };
  };
}
