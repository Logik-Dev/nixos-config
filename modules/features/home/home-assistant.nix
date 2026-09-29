# Home Assistant natif — voir docs/home-assistant-nix-plan.md.
#
# Décision du 2026-09-29 : on **repart de zéro**. Rien de ce que porte la VM
# HAOS n'est jugé essentiel, donc aucun `/config` n'est repris — ni `.storage`,
# ni les automatisations, ni les registres. Cela supprime d'un coup le blocage
# de la clé de chiffrement de l'archive, et rend sans objet la moitié des
# frictions du dossier : le « non déclarable » du §2 n'est plus un héritage à
# transporter, c'est une surface qu'on reconstruit à la main, une fois.
#
# La VM reste en service en parallèle jusqu'à validation complète. Ce qui est
# interdit n'est pas que les deux existent, c'est que les deux **possèdent les
# appareils** (§6.10). D'où, ici :
#
#   - **aucune intégration `mqtt`** : le courtier reste à la VM jusqu'à la
#     bascule. Deux HA sur le même broker commanderaient tout deux fois ;
#   - **écoute sur loopback seul**, Traefik étant la seule entrée. Aucun
#     appareil ne peut joindre cette instance, donc aucune commande accidentelle ;
#   - **son propre nom d'hôte** (`hass-native.hyper.logikdev.fr`), pendant que
#     `hass.hyper.logikdev.fr` continue de pointer sur la VM
#     (hosts/hyper/libvirt.nix). Les deux sont joignables, sans conflit.
#
# La découverte zeroconf/SSDP tourne quand même (`default_config` l'embarque) et
# fera apparaître des cartes « découvert » pour des appareils que la VM gère
# encore. C'est inerte — un flux de découverte ne commande rien tant que
# personne ne le confirme — mais n'en confirmer aucun avant la bascule.
#
# Pas encore ici, volontairement :
#   - `backups.sources` : à ajouter quand l'instance portera un état réel, pas
#     avant. Les sources de sauvegarde sont arrêtées/redémarrées autour de leur
#     passage, inutile de secouer une instance en cours de construction ;
#   - `customComponents` (alexa_media_player) et `services.music-assistant` :
#     à faire au moment où l'usage correspondant est recréé ;
#   - l'ouverture sur `br-iot` : à la bascule seulement, et **jamais loopback
#     seul à ce moment-là** — Sonos et Cast tirent les URL de média/TTS *depuis*
#     HA (§3.2 d).
{
  flake.modules.nixos.home-assistant =
    { pkgs, ... }:
    {
      notify.services = [ "home-assistant" ];

      # Nom d'hôte distinct de `hass`, qui reste sur la VM. Pas d'Authelia :
      # HA a son authentification propre, comme les autres clients natifs
      # (docs/security.md § Services hors Authelia).
      traefik.services.hass-native = {
        port = 8123;
        host = "127.0.0.1";
        category = "Maison";
        icon = "di:home-assistant";
        title = "Home Assistant (natif)";
      };

      # Le module nixpkgs ne crée pas les fichiers que l'UI écrit, et un
      # `!include` sur un fichier absent **empêche HA de démarrer**. On les
      # amorce donc vides (`[]` = liste YAML vide), une seule fois : tmpfiles
      # ne réécrit pas un fichier existant, donc ce que l'UI y mettra survit.
      systemd.tmpfiles.settings."10-home-assistant" =
        let
          seed = {
            f = {
              user = "hass";
              group = "hass";
              mode = "0644";
              argument = "[]";
            };
          };
        in
        {
          "/var/lib/hass".d = {
            user = "hass";
            group = "hass";
            mode = "0700";
          };
          "/var/lib/hass/automations.yaml" = seed;
          "/var/lib/hass/scripts.yaml" = seed;
          "/var/lib/hass/scenes.yaml" = seed;
        };

      services.home-assistant = {
        enable = true;

        # Les intégrations sont des *config flows* stockés dans `.storage`, pas
        # du YAML : le module ne peut pas en déduire les dépendances, il faut
        # les déclarer. Liste dérivée du §1.3 (l'inventaire de la VM) — elle
        # décrit ce qu'on compte **recréer**, pas ce qu'on importe, et se taille
        # à la baisse dès qu'un usage est abandonné.
        extraComponents = [
          # embarque zeroconf/ssdp/dhcp et la base
          "default_config"

          # ajoutées à la main dans la VM (hacs disparaît ; alexa_media est un
          # composant custom, à traiter le jour où l'usage est recréé)
          "jellyfin"
          "mealie"
          "meteo_france"
          "mqtt" # déclaré, délibérément non configuré avant la bascule
          "open_meteo"
          "tplink"

          # découvertes par zeroconf/ssdp/dhcp
          "androidtv_remote"
          "cast"
          "dlna_dmr"
          "ipp"
          "lifx"
          "sonos"
          "thread"

          # système / onboarding
          "analytics"
          "backup"
          "cloud" # Nabu Casa : c'est ce qui porte la copie hors-site
          "go2rtc"
          "google_translate"
          "met"
          "mobile_app"
          "radio_browser"
          "shopping_list"
          "sun"

          # créée par l'add-on Supervisor aujourd'hui ; à recréer à la main
          # contre le service natif (§1.3)
          "music_assistant"

          # pour l'alerte de fraîcheur des sauvegardes (§6 bis)
          "prometheus"
        ];

        # Mêmes versions que les dépôts HACS en service (§1.2). HACS lui-même
        # disparaît : les trois cartes sont déclarées ici.
        customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
          mini-graph-card
          apexcharts-card
        ];

        # configWritable reste à false : configuration.yaml est un lien vers le
        # store, et tout ce que l'UI écrit passe par les `!include` ci-dessous,
        # qui restent mutables dans configDir.
        config = {
          http = {
            # Loopback seul : Traefik est la seule entrée, et il attaque en
            # 127.0.0.1. S'ouvre sur `br-iot` à la bascule, pas avant.
            server_host = [ "127.0.0.1" ];
            use_x_forwarded_for = true;
            trusted_proxies = [ "127.0.0.1" ];
          };

          automation = "!include automations.yaml";
          script = "!include scripts.yaml";
          scene = "!include scenes.yaml";
        };
      };
    };
}
