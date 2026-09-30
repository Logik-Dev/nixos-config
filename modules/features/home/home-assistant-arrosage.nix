# Arrosage automatique du jardin — vanne Sonoff pilotée par Zigbee2MQTT.
#
# Repris du `/config` de l'ancienne VM HAOS, avec une correction qui change tout :
# `binary_sensor.il_va_pleuvoir` était déclaré dans un `templates.yaml`
# **syntaxiquement invalide** (`- binary_sensor:` indenté à 2 au lieu de 0), donc
# l'entité n'existait pas. Or les deux automatisations ci-dessous s'en servent
# comme condition — l'une exige `off`, l'autre `on`. Une entité absente ne
# satisfait ni l'une ni l'autre : **l'arrosage ne pouvait pas démarrer, et
# l'alerte de saut ne pouvait pas partir**. Voir §11 du dossier.
#
# Dépendances externes, à recréer sur l'instance native avant que tout ceci
# s'anime : l'intégration `meteo_france` (les deux capteurs ci-dessous), la
# découverte MQTT de la vanne via Zigbee2MQTT, et l'enregistrement `mobile_app`
# du téléphone pour les notifications.
_:
let
  arrosageModule =
    _:
    let
      meteo = "sensor.meteo_france_forecast_for_city_leognan_aquitaine_33_fr_leognan";
      pluieMm = "${meteo}_daily_precipitation";
      pluiePct = "${meteo}_rain_chance";

      vanne = "switch.vanne_sonoff";
      telephone = "notify.mobile_app_iphone_de_cedric";
      pleut = "binary_sensor.il_va_pleuvoir";
    in
    {
      # Le seuil combine les deux prévisions : il ne suffit pas qu'il soit
      # *probable* qu'il pleuve, il faut aussi une quantité qui dispense
      # d'arroser. `unique_id` ajouté au passage — absent de la version VM, il
      # permet de renommer l'entité sans casser ce qui la référence.
      services.home-assistant.config.template = [
        {
          binary_sensor = [
            {
              name = "Il va pleuvoir";
              unique_id = "il_va_pleuvoir";
              state = "{{ states('${pluieMm}') | float(0) > 2 and states('${pluiePct}') | float(0) > 30 }}";
            }
          ];
        }
      ];

      homeAssistant.automations = {
        arrosage_automatique = {
          alias = "Arrosage — cycle du matin";
          description = "Ouvre la vanne au lever du soleil, sauf si de la pluie est prévue.";
          triggers = [
            {
              trigger = "sun";
              event = "sunrise";
              offset = 0;
            }
          ];
          conditions = [
            {
              condition = "state";
              entity_id = pleut;
              state = "off";
            }
          ];
          variables.duree_minutes = 5;
          actions = [
            {
              action = telephone;
              data = {
                title = "Arrosage automatique";
                message = "L'arrosage va démarrer pour {{ duree_minutes }} minutes.";
              };
            }
            {
              action = "switch.turn_on";
              target.entity_id = vanne;
            }
            { delay.minutes = "{{ duree_minutes }}"; }
            {
              action = "switch.turn_off";
              target.entity_id = vanne;
            }
            {
              action = telephone;
              data = {
                title = "Fin de l'arrosage";
                message = "Fermeture de la vanne Sonoff.";
              };
            }
          ];
          mode = "single";
        };

        # Filet de sécurité indépendant du cycle : si la vanne reste ouverte
        # — cycle interrompu, commande manuelle oubliée, redémarrage de HA en
        # plein arrosage — elle se referme seule. C'est la seule automatisation
        # du lot qui ne dépendait d'aucune entité cassée, et la plus importante :
        # elle protège contre un dégât des eaux.
        arrosage_fermeture_securite = {
          alias = "Arrosage — fermeture de sécurité";
          description = "Ferme la vanne si elle reste ouverte plus de 10 minutes.";
          triggers = [
            {
              trigger = "state";
              entity_id = [ vanne ];
              to = "on";
              for.minutes = 10;
            }
          ];
          actions = [
            {
              action = "switch.turn_off";
              target.entity_id = vanne;
            }
            {
              action = telephone;
              data = {
                title = "⚠️ Arrosage — sécurité";
                message = "Vanne fermée automatiquement après 10 min.";
              };
            }
          ];
          mode = "single";
        };

        # Le pendant de la condition du cycle : dire *pourquoi* rien ne s'est
        # passé. Sans ça, un matin sans arrosage est indistinguable d'une panne.
        arrosage_notification_pluie = {
          alias = "Arrosage — annulé pour cause de pluie";
          description = "Explique l'absence d'arrosage quand la pluie l'a emporté.";
          triggers = [
            {
              trigger = "time";
              at = "07:00:00";
            }
          ];
          conditions = [
            {
              condition = "state";
              entity_id = pleut;
              state = "on";
            }
          ];
          actions = [
            {
              action = telephone;
              data = {
                title = "Arrosage annulé";
                # `states('...')` plutôt que `states.sensor.…` : la forme objet
                # lève une erreur si l'entité manque, la forme fonction rend
                # simplement « unknown ».
                message = "Pluie prévue dans les 24 h — {{ states('${pluiePct}') }} % de risque, {{ states('${pluieMm}') }} mm attendus.";
              };
            }
          ];
          mode = "single";
        };
      };
    };
in
{
  flake.modules.nixos.home-assistant.imports = [ arrosageModule ];
}
