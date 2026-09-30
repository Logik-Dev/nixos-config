# Tableau de bord Home Assistant, déclaré en nix.
#
# `lovelaceConfig` bascule le tableau de bord en mode YAML et
# `lovelaceConfigWritable` reste à `false` : le fichier est un lien vers le
# store, donc il n'est pas éditable depuis l'UI. C'est le compromis assumé du
# §2 du dossier — on échange l'éditeur graphique contre du versionné. Le
# tableau de bord créé par défaut à l'onboarding reste disponible à côté, pour
# bricoler.
#
# Cinq vues, construites sur l'inventaire réel des entités du 2026-09-30, pas
# sur ce qu'on aimerait avoir. Chaque entité citée ici existe.
#
# Deux choses à savoir si on le modifie :
#
#   - **les listes gardent leur ordre en nix, les attrsets non** (§13). L'ordre
#     des vues, des sections et des cartes est donc fiable ; ne jamais faire
#     dépendre quoi que ce soit de l'ordre des clés d'une carte.
#   - `custom:mini-graph-card` et `custom:apexcharts-card` ne fonctionnent que
#     parce qu'ils sont déclarés dans `customLovelaceModules`
#     (home-assistant.nix). Ajouter une autre carte HACS demande de la déclarer
#     là-bas d'abord.
_:
let
  dashboardModule =
    { ... }:
    let
      # Le préfixe Météo-France est illisible et répété huit fois : il dépend de
      # la ville configurée dans l'intégration. S'il change, c'est ici.
      mf = "sensor.meteo_france_forecast_for_city_leognan_aquitaine_33_fr_leognan";
      meteo = "weather.meteo_france_forecast_for_city_leognan_aquitaine_33_fr_leognan";

      vanne = "switch.vanne_sonoff";
      priseTele = "prise_de_la_tele";
      prisePlan = "prise_du_plan_de_travail";

      # Identifiants mis à jour le 2026-09-30 après renommage côté UI. C'est le
      # coût du tableau de bord déclaratif : renommer une entité dans HA casse
      # les références nix, et les cartes concernées s'affichent en erreur
      # jusqu'à ce que le dépôt suive. Le contrôle d'existence des entités
      # (§15) est ce qui rend ce coût gérable — il liste les manquantes avant
      # qu'on les découvre à l'écran.
      sonos = {
        salon = "media_player.sonos_salon";
        cuisine = "media_player.sonos_cuisine";
        enfants = "media_player.sonos_chambre_des_enfants";
      };

      # Un seul téléviseur — une TCL Smart TV Pro sous Google TV, à
      # 192.168.21.187 — mais **deux intégrations**, donc deux entités qui ne
      # font pas la même chose :
      #
      #   - `androidtv_remote` : allumer, éteindre, naviguer, lancer une appli.
      #     C'est elle qui annonçait un récepteur AirPlay en mDNS (seul appareil
      #     du VLAN avec le port 7000 ouvert, §14) ;
      #   - `cast` : ce qui est en cours de diffusion, et le volume associé.
      #
      # HA ne peut pas les fusionner : les deux intégrations identifient
      # l'appareil différemment — par la MAC pour l'une, par l'UUID Cast pour
      # l'autre. Ce n'est donc pas un doublon à corriger, c'est un appareil vu
      # deux fois. Les noms de carte ci-dessous disent laquelle fait quoi.
      tvCommande = "media_player.tv_salon";
      tvDiffusion = "media_player.tv_salon_cast";
      tvTelecommande = "remote.tv_salon";

      # Gabarits — le même motif revenait quinze fois.
      heading = icon: text: {
        type = "heading";
        inherit icon;
        heading = text;
        heading_style = "title";
      };

      sousTitre = text: {
        type = "heading";
        heading = text;
        heading_style = "subtitle";
      };

      tuile = entity: { inherit entity; type = "tile"; };

      tuileNommee = entity: name: {
        inherit entity name;
        type = "tile";
      };

      interrupteur = entity: {
        inherit entity;
        type = "tile";
        features = [ { type = "toggle"; } ];
      };

      lecteur = entity: {
        inherit entity;
        type = "tile";
        features = [
          { type = "media-player-volume-slider"; }
          {
            type = "media-player-playback";
            controls = [
              "shuffle"
              "previous"
              "play_pause"
              "next"
              "repeat"
            ];
          }
        ];
      };

      # Puissance instantanée d'une prise, en courbe.
      courbePuissance = prise: nom: {
        type = "custom:mini-graph-card";
        name = nom;
        entities = [ "sensor.${prise}_consommation_actuelle" ];
        hours_to_show = 24;
        points_per_hour = 4;
        line_width = 3;
        animate = true;
        show = {
          fill = "fade";
          extrema = true;
        };
      };

      renommer = carte: nom: carte // { name = nom; };

      grille = cards: { inherit cards; type = "grid"; };
    in
    {
      # Le module calcule cette entrée dès que `lovelaceConfig` est défini, mais
      # sans `title` : la barre latérale afficherait un libellé par défaut. On la
      # redéclare en entier — l'option porte l'attrset complet, donc la définir
      # remplace le défaut plutôt que de le compléter.
      services.home-assistant.config.lovelace.dashboards.nixos-lovelace = {
        mode = "yaml";
        filename = "ui-lovelace.yaml";
        title = "Maison";
        icon = "mdi:home-heart";
        show_in_sidebar = true;
      };

      services.home-assistant.lovelaceConfig = {
        title = "Maison";

        views = [
          # ── 1 ─────────────────────────────────────────── vue d'accueil ──
          {
            title = "Accueil";
            path = "accueil";
            icon = "mdi:home";
            type = "sections";
            max_columns = 3;

            # Les badges portent ce qu'on veut savoir sans lire : est-ce qu'il
            # va pleuvoir, est-ce que la vanne est ouverte, où est le téléphone.
            badges = [
              {
                type = "entity";
                entity = "binary_sensor.il_va_pleuvoir";
                name = "Pluie prévue";
              }
              {
                type = "entity";
                entity = vanne;
                name = "Arrosage";
              }
              {
                type = "entity";
                entity = "device_tracker.iphone_de_cedric";
                name = "Cédric";
              }
              {
                type = "entity";
                entity = "sensor.rankoder_transcoding";
                name = "Transcodages";
              }
            ];

            sections = [
              (grille [
                (heading "mdi:weather-partly-cloudy" "Météo")
                {
                  type = "weather-forecast";
                  entity = meteo;
                  forecast_type = "daily";
                  show_current = true;
                  show_forecast = true;
                }
                (tuileNommee "${mf}_rain_chance" "Risque de pluie")
                (tuileNommee "${mf}_uv" "Indice UV")
                # L'alerte départementale ne s'affiche que quand elle dit
                # autre chose que « vert » : une carte permanente à « vert »
                # n'apprend rien et occupe de la place.
                {
                  type = "tile";
                  entity = "sensor.meteo_france_alert_for_department_33_33_weather_alert";
                  name = "Vigilance Gironde";
                  visibility = [
                    {
                      condition = "state";
                      entity = "sensor.meteo_france_alert_for_department_33_33_weather_alert";
                      state_not = "Vert";
                    }
                  ];
                }
              ])

              (grille [
                (heading "mdi:speaker-multiple" "Musique")
                (lecteur sonos.salon)
                (lecteur sonos.cuisine)
                (lecteur sonos.enfants)
              ])

              (grille [
                (heading "mdi:television-play" "Télévision")
                # Les deux entités portent le nom de leur appareil, donc elles
                # s'affichent toutes deux « TV Google » / « Smart TV » sans dire
                # ce qu'elles font. Les noms explicites sont posés ici.
                (renommer (lecteur tvCommande) "TV — commande")
                (renommer (lecteur tvDiffusion) "TV — diffusion")
                # La télécommande sert quand l'application au premier plan ne
                # répond pas aux commandes de lecture — fréquent sur Android TV,
                # où toutes les applis n'implémentent pas le protocole média.
                (tuileNommee tvTelecommande "TV — télécommande")
              ])

              (grille [
                (heading "mdi:cart" "Maison")
                {
                  type = "todo-list";
                  entity = "todo.liste_d_achats";
                }
                (tuileNommee "sensor.iphone_de_cedric_battery_level" "Batterie iPhone")
              ])
            ];
          }

          # ── 2 ────────────────────────────────────────────── arrosage ──
          {
            title = "Arrosage";
            path = "arrosage";
            icon = "mdi:sprinkler-variant";
            type = "sections";
            max_columns = 3;

            sections = [
              (grille [
                (heading "mdi:valve" "Vanne")
                (interrupteur vanne)
                (tuileNommee "binary_sensor.vanne_sonoff_valve_work_state" "État de la vanne")
                (tuileNommee "sensor.vanne_sonoff_current_device_status" "Diagnostic")
                (sousTitre "Sécurité")
                # Le filet anti-dégât des eaux : c'est l'automatisation la plus
                # importante du lot, elle mérite d'être visible et non enfouie
                # dans les réglages.
                (tuileNommee "automation.arrosage_fermeture_de_securite" "Fermeture après 10 min")
                (tuileNommee "switch.vanne_sonoff_auto_close_when_water_shortage" "Coupure si manque d'eau")
              ])

              (grille [
                (heading "mdi:water" "Consommation")
                (tuileNommee "sensor.vanne_sonoff_daily_irrigation_volume" "Volume du jour")
                (tuileNommee "sensor.vanne_sonoff_real_time_irrigation_volume" "Volume en cours")
                (tuileNommee "sensor.vanne_sonoff_real_time_irrigation_duration" "Durée en cours")
                (tuileNommee "sensor.vanne_sonoff_flow" "Débit")
                {
                  type = "custom:apexcharts-card";
                  header = {
                    show = true;
                    title = "Volume arrosé par jour";
                    show_states = false;
                  };
                  graph_span = "14d";
                  span.end = "day";
                  series = [
                    {
                      entity = "sensor.vanne_sonoff_daily_irrigation_volume";
                      type = "column";
                      group_by = {
                        func = "max";
                        duration = "1d";
                      };
                    }
                  ];
                }
              ])

              (grille [
                (heading "mdi:cloud-question" "Ce qui décide")
                # La condition des deux automatisations. Si ce capteur est
                # indisponible, l'arrosage ne démarre pas — c'est exactement le
                # défaut hérité de la VM (§11), donc il se surveille ici.
                (tuileNommee "binary_sensor.il_va_pleuvoir" "Pluie prévue")
                (tuileNommee "${mf}_rain_chance" "Risque de pluie")
                (tuileNommee "${mf}_daily_precipitation" "Précipitations du jour")
                (sousTitre "Matériel")
                (tuileNommee "sensor.vanne_sonoff_battery" "Batterie de la vanne")
                (tuileNommee "update.vanne_sonoff" "Micrologiciel")
              ])
            ];
          }

          # ── 3 ─────────────────────────────────────────────── énergie ──
          {
            title = "Énergie";
            path = "energie";
            icon = "mdi:flash";
            type = "sections";
            max_columns = 2;

            badges = [
              {
                type = "entity";
                entity = "sensor.${prisePlan}_consommation_actuelle";
                name = "Plan de travail";
              }
              {
                type = "entity";
                entity = "sensor.${priseTele}_consommation_actuelle";
                name = "Télé";
              }
            ];

            sections = [
              (grille [
                (heading "mdi:countertop" "Plan de travail")
                (interrupteur "switch.${prisePlan}")
                (courbePuissance prisePlan "Puissance sur 24 h")
                (tuileNommee "sensor.${prisePlan}_consommation_d_aujourd_hui" "Aujourd'hui")
                (tuileNommee "sensor.${prisePlan}_consommation_de_ce_mois_ci" "Ce mois-ci")
                (sousTitre "Diagnostic")
                (tuileNommee "sensor.${prisePlan}_tension" "Tension")
                (tuileNommee "sensor.${prisePlan}_niveau_de_signal" "Signal Wi-Fi")
                # Une prise en surcharge est un risque matériel : visible
                # seulement quand c'est vrai, mais alors impossible à manquer.
                {
                  type = "tile";
                  entity = "binary_sensor.${prisePlan}_surcharge";
                  name = "⚠️ Surcharge";
                  visibility = [
                    {
                      condition = "state";
                      entity = "binary_sensor.${prisePlan}_surcharge";
                      state = "on";
                    }
                  ];
                }
              ])

              (grille [
                (heading "mdi:television" "Télé")
                (interrupteur "switch.${priseTele}")
                (courbePuissance priseTele "Puissance sur 24 h")
                (tuileNommee "sensor.${priseTele}_consommation_d_aujourd_hui" "Aujourd'hui")
                (tuileNommee "sensor.${priseTele}_consommation_de_ce_mois_ci" "Ce mois-ci")
                (sousTitre "Diagnostic")
                (tuileNommee "sensor.${priseTele}_tension" "Tension")
                (tuileNommee "sensor.${priseTele}_niveau_de_signal" "Signal Wi-Fi")
                {
                  type = "tile";
                  entity = "binary_sensor.${priseTele}_surcharge";
                  name = "⚠️ Surcharge";
                  visibility = [
                    {
                      condition = "state";
                      entity = "binary_sensor.${priseTele}_surcharge";
                      state = "on";
                    }
                  ];
                }
              ])
            ];
          }

          # ── 4 ────────────────────────────────────────────── rankoder ──
          {
            title = "Rankoder";
            path = "rankoder";
            icon = "mdi:movie-cog";
            type = "sections";
            max_columns = 3;

            badges = [
              {
                type = "entity";
                entity = "sensor.rankoder_pending_approval";
                name = "En attente";
              }
              {
                type = "entity";
                entity = "sensor.rankoder_space_saved";
                name = "Espace gagné";
              }
            ];

            sections = [
              (grille [
                (heading "mdi:cogs" "File de traitement")
                (tuileNommee "sensor.rankoder_transcoding" "En cours")
                (tuileNommee "sensor.rankoder_pending_approval" "En attente d'approbation")
                (tuileNommee "sensor.rankoder_done" "Terminés")
                (tuileNommee "sensor.rankoder_skipped" "Ignorés")
              ])

              (grille [
                (heading "mdi:harddisk" "Gain d'espace")
                {
                  type = "custom:mini-graph-card";
                  name = "Espace gagné (30 j)";
                  entities = [ "sensor.rankoder_space_saved" ];
                  hours_to_show = 720;
                  points_per_hour = 0.5;
                  line_width = 3;
                  show = {
                    fill = "fade";
                    extrema = true;
                  };
                }
                (tuileNommee "sensor.rankoder_space_saved" "Total cumulé")
              ])

              (grille [
                (heading "mdi:alert-circle" "Échecs")
                (tuileNommee "sensor.rankoder_failed" "Nombre d'échecs")
                # Le détail du dernier échec n'a de sens que s'il y en a eu un.
                {
                  type = "tile";
                  entity = "sensor.rankoder_last_failure";
                  name = "Dernier échec";
                  visibility = [
                    {
                      condition = "numeric_state";
                      entity = "sensor.rankoder_failed";
                      above = 0;
                    }
                  ];
                }
                (sousTitre "Automatisations")
                (tuileNommee "automation.rankoder_reception_demande_d_approbation" "Demande d'approbation")
                (tuileNommee "automation.rankoder_traitement_de_la_reponse" "Traitement de la réponse")
                (tuileNommee "automation.rankoder_echec_de_transcodage" "Alerte d'échec")
                (tuileNommee "sensor.rankoder_version" "Version")
              ])
            ];
          }

          # ── 5 ─────────────────────────────────────────────── système ──
          {
            title = "Système";
            path = "systeme";
            icon = "mdi:cog";
            type = "sections";
            max_columns = 3;

            sections = [
              (grille [
                (heading "mdi:backup-restore" "Sauvegardes")
                # Celles de HA lui-même. Le vrai filet est ailleurs — restic sur
                # /var/lib/hass et pgBackRest pour l'enregistreur (§8 B0 et §10)
                # — mais une fraîcheur qui décroche ici est un signal utile.
                (tuileNommee "sensor.backup_backup_manager_state" "État")
                (tuileNommee "sensor.backup_last_successful_automatic_backup" "Dernière réussie")
                (tuileNommee "sensor.backup_next_scheduled_automatic_backup" "Prochaine")
              ])

              (grille [
                (heading "mdi:zigbee" "Zigbee")
                # Le pont, pas les objets : si la connexion décroche, tout le
                # Zigbee devient muet — c'est la panne qui a duré 2,5 jours dans
                # la VM (P0-9) sans que rien ne le dise.
                (tuileNommee "binary_sensor.zigbee2mqtt_bridge_connection_state" "Connexion au courtier")
                (tuileNommee "sensor.zigbee2mqtt_bridge_version" "Version")
                (interrupteur "switch.zigbee2mqtt_bridge_permit_join")
              ])

              (grille [
                (heading "mdi:robot" "Automatisations")
                (tuileNommee "automation.arrosage_cycle_du_matin" "Arrosage — cycle du matin")
                (tuileNommee "automation.arrosage_fermeture_de_securite" "Arrosage — sécurité")
                (tuileNommee "automation.arrosage_annule_pour_cause_de_pluie" "Arrosage — annulé (pluie)")
                (sousTitre "Présence")
                (tuile "person.cedric_maunier")
                (tuileNommee "device_tracker.iphone_de_cedric" "iPhone")
              ])
            ];
          }
        ];
      };
    };
in
{
  flake.modules.nixos.home-assistant.imports = [ dashboardModule ];
}
