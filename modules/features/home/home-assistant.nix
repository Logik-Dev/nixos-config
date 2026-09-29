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
#   - **son propre nom d'hôte** (`ha.hyper.logikdev.fr`), pendant que
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

      # Découverte des objets — **uniquement sur le lien IoT**.
      #
      # mDNS (5353) et SSDP (1900) sont du multicast : les réponses n'arrivent
      # pas sur le tuple de la requête, donc le suivi de connexion ne les
      # rattrape pas et le pare-feu les jette. Sans ces deux ports, HA émet ses
      # requêtes et n'entend jamais personne.
      #
      # Scopé à `br-iot` et pas ouvert globalement : c'est là que vivent les
      # objets (§3.2 b), et ça évite d'exposer la découverte au LAN, au tailnet
      # et aux VLAN 100/200. La contrepartie assumée est qu'un objet compromis
      # peut annoncer un faux service en mDNS — mais un flux de découverte ne
      # commande rien tant que personne ne le confirme dans l'UI.
      #
      # ⚠️ Ceci ne suffit pas seul. HA choisit son adaptateur mDNS d'après la
      # route par défaut, donc il se liait à `management` (le LAN) et
      # n'entendait rien du VLAN IoT. L'adaptateur se sélectionne dans
      # `.storage/core.network`, via l'UI — Paramètres → Système → Réseau. Il
      # n'existe aucune option nix pour ça (§3.2 a).
      #
      # 8123 reste délibérément FERMÉ sur `br-iot` : la découverte n'en a pas
      # besoin. Il ne s'ouvrira que le jour où Cast ou Sonos seront ajoutés —
      # ces appareils vont chercher les URL de média et de TTS *depuis* HA
      # (§3.2 d) — et ce sera une exposition à décider à ce moment-là, pas une
      # avance prise « au cas où ».
      networking.firewall.interfaces."br-iot".allowedUDPPorts = [
        5353 # mDNS / zeroconf
        1900 # SSDP / UPnP
      ];

      # Enregistreur sur PostgreSQL plutôt que sur le SQLite par défaut.
      # Tranché le 2026-09-29 : le §6.8 différait ce choix parce qu'il coûtait
      # « une migration d'historique ou sa perte ». En repartant de zéro ce coût
      # n'existe pas, et il ne redeviendra jamais nul — donc c'est maintenant.
      #
      # Ce que ça apporte : HA entre dans le PITR pgBackRest. La stanza est
      # unique (`default`, cluster local), donc une base de plus est couverte
      # automatiquement, sur les deux dépôts — USB et Hetzner hors-site.
      #
      # Connexion en peer par la socket Unix, comme n8n/vaultwarden/authelia :
      # le service tourne sous l'utilisateur `hass`, `pg_hba` a
      # `local all all peer`, donc **aucun mot de passe et aucun secret agenix**.
      # `ensureDBOwnership` impose que le nom de la base == le nom du rôle, d'où
      # `hass` et non `homeassistant`.
      services.postgresql = {
        ensureDatabases = [ "hass" ];
        ensureUsers = [
          {
            name = "hass";
            ensureDBOwnership = true;
          }
        ];
      };

      # L'ordonnancement est déjà posé par le module nixpkgs
      # (`after = [ … "postgresql.target" ]`), rien à ajouter ici.

      # Le répertoire de config ne porte plus l'historique : il reste petit et
      # stable. D'où `manageService = false` — pas de redémarrage nocturne de
      # HA, ce qui compense en partie le coût assumé au §3.3. Les fichiers de
      # `.storage/` sont écrits par renommage atomique, donc une copie à chaud
      # les attrape entiers. Ce qui mérite vraiment de la cohérence — l'historique
      # — est dans postgres, avec du PITR.
      backups.sources.home-assistant = {
        paths = [ "/var/lib/hass" ];
        manageService = false;
        exclude = [
          "home-assistant.log*"
          "tts/"
          "deps/"
        ];
      };

      # Nom d'hôte distinct de `hass`, qui reste sur la VM. Pas d'Authelia :
      # HA a son authentification propre, comme les autres clients natifs
      # (docs/security.md § Services hors Authelia).
      traefik.services.ha = {
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

        # Pilote PostgreSQL de l'enregistreur. Sans lui, HA retombe en erreur
        # sur `db_url` au lieu de démarrer.
        extraPackages = python3Packages: with python3Packages; [ psycopg2 ];

        # Mêmes versions que les dépôts HACS en service (§1.2). HACS lui-même
        # disparaît : les trois cartes sont déclarées ici.
        customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
          mini-graph-card
          apexcharts-card
        ];

        # configWritable reste à false : configuration.yaml est un lien vers le
        # store, et tout ce que l'UI écrit passe par les `!include` ci-dessous,
        # qui restent mutables dans configDir.
        #
        # PAS de bloc `http` ici, et ce n'est pas un oubli. Depuis HA 2026.8 la
        # configuration `http` vit dans `.storage/http` et l'YAML n'est plus
        # qu'une **migration one-shot** :
        #
        #   - au premier démarrage, l'YAML est importé comme config `pending`,
        #     l'ancienne restant `stable` ;
        #   - `pending` doit être **promue dans les 5 minutes** via l'API
        #     WebSocket, donc depuis une session authentifiée ;
        #   - sans promotion, HA revient à `stable`, redémarre, et marque la
        #     pending `error: not_promoted` — *« kept for inspection but never
        #     applied again »*. Elle est définitivement écartée ;
        #   - `yaml_migration_done` est alors posé : l'YAML n'est plus relu.
        #
        # Sur une instance neuve derrière un proxy, c'est un piège fermé : on ne
        # peut pas s'authentifier pour promouvoir, puisque HA renvoie 400 à
        # toute requête portant un `X-Forwarded-For` non fiable — et Traefik en
        # pose toujours un. Vécu le 2026-09-29 : le 302 initial n'était qu'une
        # fenêtre de 5 minutes avant révocation.
        #
        # Donc : HA démarre sur ses défauts, l'onboarding se fait **hors proxy**
        # (`ssh -L 8123:127.0.0.1:8123 hyper`), et le reverse proxy se règle
        # ensuite dans l'UI — Paramètres → Système → Réseau — où la promotion se
        # fait proprement. 8123 reste absent d'`allowedTCPPorts`, donc le bind
        # par défaut sur 0.0.0.0 n'est joignable depuis aucune interface.
        config = {
          # Socket Unix + auth peer : pas d'hôte dans l'URL, pas de mot de passe.
          # `purge_keep_days` est laissé au défaut de HA (10 j) faute de base
          # pour choisir autre chose — c'est le bouton à tourner si l'historique
          # doit durer plus longtemps, en gardant à l'esprit que ça pèse aussi
          # sur les WAL et donc sur pgBackRest.
          recorder.db_url = "postgresql://@/hass";

          # INDISPENSABLE, et ce n'est pas redondant avec `extraComponents`.
          # Cette liste-là n'ajoute que les dépendances Python au **paquet** ;
          # c'est cette clé qui dit à HA de **charger** l'intégration. Omise au
          # départ, elle a coûté : `mobile_app` n'était pas chargé (l'app
          # répondait « le composant mobile_app n'est pas chargé »), et pas
          # davantage `zeroconf`/`ssdp`/`dhcp`, `webhook`, `history`,
          # `logbook`, `media_source`…
          #
          # Seules fonctionnaient les intégrations possédant une entrée de
          # configuration dans `.storage` — HA les charge indépendamment du
          # YAML — ce qui rendait la panne d'autant moins lisible : l'UI avait
          # l'air normale.
          #
          # `default_config` couvre `mobile_app` : pas besoin de le déclarer en
          # plus. C'est aussi ce que portait le `configuration.yaml` de la VM.
          default_config = { };

          automation = "!include automations.yaml";
          script = "!include scripts.yaml";
          scene = "!include scenes.yaml";
        };
      };
    };
}
