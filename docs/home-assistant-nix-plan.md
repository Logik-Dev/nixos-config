# Dossier — Home Assistant vers une approche nix déclarative

> Statut : **inventaire terminé**, décision à prendre. Aucune modification appliquée.
> Date : 2026-09-28 — **révisé le 2026-09-29** (§3.2 réécrit : la question du VLAN
> est tranchée, et l'analyse a mis au jour SEC-14, hors périmètre).
> Méthode : lecture seule via l'API HA (jeton longue durée, tunnel SSH), plus
> inspection de l'hôte et de nixpkgs. La VM n'a pas été touchée.
> Lié : `docs/resource-control-plan.md` (C2 — la VM immobilise 15,6 G pour 0,5 G utilisés).
>
> **Conclusion : migrer, en natif (`services.home-assistant`).** L'inventaire a
> retiré les deux objections qui faisaient pencher vers le conteneur, et le seul
> point dur (AirSonos) est **résolu : l'add-on est supprimable** (§3.1).
> **Plus aucun bloqueur technique.**
>
> **Décision du 2026-09-29 : on repart de zéro.** Rien de ce que porte la VM
> n'est jugé essentiel : **aucun `/config` n'est repris** — ni `.storage`, ni
> les automatisations, ni les registres. Conséquences, qui simplifient
> massivement le dossier : l'archive chiffrée n'est plus un blocage (§6.3), la
> reprise de `/config` disparaît (§6.4), et le « non déclarable » du §2 cesse
> d'être un héritage à transporter pour devenir une surface qu'on reconstruit à
> la main, une fois. Le découpage en lots est en §8.

## 1. État des lieux (mesuré)

| Élément | Constat |
|---|---|
| HA Core | **2026.9.4**, `state=RUNNING`, 220 composants chargés, 390 entités |
| HAOS | **18.3** — alors que l'image s'appelle `haos_ova-16.3.qcow2` : l'OS s'est mis à jour **en OTA**. C'est une fonction réellement utilisée, donc réellement perdue |
| Supervisor | 2026.09.2 |
| Image | **31 G** de qcow2 sur le disque système |
| Mémoire | 16 G alloués, `unused=15,1 G` → ~0,5 G utilisés. `memballoon virtio` **déjà présent** |
| Passthrough matériel | **aucun** (`hostdev` absent) |
| Dongle Zigbee | **sur l'hôte** (`/dev/ttyUSB0` → `services.zigbee2mqtt`), HA le voit via MQTT |
| Réseau | `br-iot`, 192.168.21.181 — **l'hôte est sur le même lien** (192.168.21.241) |
| Recorder | SQLite interne (aucune base `homeassistant` dans PostgreSQL) |
| **Sauvegarde** | **elle existe** — sauvegardes automatiques HA quotidiennes, rétention 3 copies, base incluse, chiffrées, vers **deux agents** : `hassio.local` (dans la VM) **et `cloud.cloud`** (Nabu Casa, hors-site). Dernière réussie : 2026-09-28 21:10, 109 Mio. Voir §1.4 pour le vrai périmètre du manque |
| nixpkgs | `home-assistant` **2026.8.3** → **un mineur de retard** sur les 2026.9.4 en service |

### 1.1 Add-ons — il y en a cinq, pas trois

Correction de méthode : un scan de ports ne voit pas les add-ons HAOS, qui passent
par **Ingress** (proxy interne sur le 8123). L'inventaire fiable vient des entités
`update.*`, qui ont révélé deux add-ons non mentionnés.

| Add-on | Version | Devenir hors Supervisor |
|---|---|---|
| **Music Assistant** | 2.10.4 | **`services.music-assistant` existe dans nixpkgs** (`nixos/modules/services/audio/music-assistant.nix`, paquet 2.9.13, un mineur de retard) → natif et déclaratif |
| **AirSonos** | 5.2.1 (MAJ 5.2.3 en attente) | **à supprimer** — inutilisé, aucun remplacement nécessaire (§3.1) |
| Studio Code Server | 7.1.1 (MAJ 7.2.0) | **disparaît par construction** : édite le YAML dans la VM ; en déclaratif on édite dans le dépôt |
| Terminal & SSH | 10.5.0 | disparaît : le shell de l'hôte le remplace |
| Get HACS | 1.3.1 | jetable : ne sert qu'à installer HACS |

### 1.2 HACS — quatre dépôts, dont trois déjà dans nixpkgs

| Dépôt HACS | Version installée | Dans nixpkgs ? |
|---|---|---|
| `mini-graph-card` | v0.13.0 | **oui — 0.13.0, version identique** (`home-assistant-custom-lovelace-modules`) |
| `apexcharts-card` | v2.2.3 | **oui — 2.2.3, version identique** |
| `alexa_media_player` | v5.16.1 | **non** → à packager en `customComponents` (dérivation courte) |
| HACS lui-même | 2.0.5 | sans objet : **devient inutile** si les trois autres sont déclarés |

**HACS peut donc disparaître.** C'est l'inverse de l'hypothèse de départ, qui en
faisait la friction de fond : le compromis « `configDir` inscriptible » n'est pas
nécessaire ici.

### 1.3 Intégrations — 31 entrées, dont 8 ajoutées à la main

| Source | Nb | Détail |
|---|---|---|
| `user` (ajout manuel) | **8** | alexa_media, hacs, jellyfin, mealie, meteo_france, mqtt, open_meteo, tplink |
| `zeroconf` / `ssdp` / `dhcp` / `integration_discovery` | **9** | androidtv_remote, cast, ipp, sonos, thread, dlna_dmr, lifx, tplink ×2 — **découvertes automatiquement** |
| `system` | 5 | analytics, backup, cloud, go2rtc, **hassio** |
| `onboarding` | 4 | google_translate, met, radio_browser, shopping_list |
| `registration` | 3 | mobile_app (téléphones) |
| `hassio` | 1 | **music_assistant** — créée par l'add-on |
| `import` | 1 | sun |

Deux entrées sont des artefacts du Supervisor et disparaîtraient : `hassio`, et
surtout **`music_assistant` (`source=hassio`)** — l'add-on l'avait auto-découverte.
Elle devra être recréée à la main vers l'URL du service natif. Les 9 entrées
découvertes se recréeront toutes seules, à condition que la découverte reste sur le
bon lien (§3.2).

État de santé actuel, au passage : **4 entrées ne chargent pas.**

| Entrée | État | Raison |
|---|---|---|
| **mealie** | `setup_error` | **`auth_failed`** — vrai bug, à corriger indépendamment de tout ça |
| lifx | `setup_retry` | délai dépassé (ampoule hors tension) — normal |
| androidtv_remote | `setup_retry` | TV éteinte — normal |
| ipp | `setup_retry` | imprimante éteinte — normal |

### 1.4 Sauvegardes — correction d'une affirmation fausse

Une révision antérieure de ce document affirmait que HA n'avait **aucune**
sauvegarde. **C'est faux.** L'API le démontre :

| Élément | Valeur |
|---|---|
| Sauvegardes automatiques | **configurées et fonctionnelles** (`recurrence: daily`) |
| Dernière réussie | **2026-09-28 21:10** (109 Mio, base de données incluse, chiffrée) |
| Prochaine | 2026-09-29 04:57 |
| Rétention | 3 copies |
| Agents de destination | **`hassio.local`** (dans la VM) **et `cloud.cloud`** (Nabu Casa) |
| Add-ons inclus | tous (`include_all_addons: true`) |

**Il existe donc déjà une copie hors-site**, via Nabu Casa. L'affirmation « le
service le plus critique du foyer est le seul non sauvegardé » était erronée et ne
doit pas servir d'argument.

Le manque réel est plus étroit, et reste à traiter :

1. **Aucune copie sur site en dehors de la VM.** Si le disque de la VM est perdu ou
   corrompu, la restauration dépend d'Internet, d'un abonnement Nabu Casa actif et
   de la clé de chiffrement.
2. **Hors du pipeline surveillé.** Ces sauvegardes ne passent ni par restic, ni par
   les vérifications, ni par les *restore drills*, et **rien n'alerte** si elles
   cessent. `sensor.backup_last_successful_automatic_backup` existe pourtant et est
   directement exploitable.
3. **La clé de chiffrement est indispensable à la restauration** et vit dans la
   configuration de HA. Elle doit être dans Vaultwarden — sans elle, les copies
   Nabu Casa sont inexploitables.

État au 2026-09-28 : une copie de la dernière sauvegarde a été déposée sur hyper
dans `/mnt/local/ha-backups/` (109 Mio, vérifiée). C'est un geste **ponctuel**, pas
encore un dispositif — voir §6 bis.

### 1.5 Le YAML — la mesure qui décide

17 automatisations, 14 scripts. Les identifiants les départagent :

| Origine | Nb | Exemples |
|---|---|---|
| **YAML écrit à la main** (id en slug) | **10** | `rankoder_approval_request`, `rankoder_deliver_deferred`, `rankoder_handle_action`, `musique_voix_lea`, `musique_playlist_charlotte`… |
| Éditeur graphique (id numérique) | 7 | `1768941404192`, `1780832170509`… |

Ce sont les dix écrites à la main qui comptent : **tout le workflow d'approbation
`rankoder`** — un service déclaré dans ce dépôt (`medias/rankoder.nix`) — et les
automatisations musique personnalisées. Les automatisations rankoder appartiennent
conceptuellement au dépôt, à côté du module qui déclare le service qu'elles
pilotent. **C'est un gain déclaratif réel, pas de l'esthétique.**

Nuance à ne pas confondre : **l'éditeur graphique écrit lui aussi dans
`automations.yaml`.** Les automatisations sont donc déjà versionnables quelle que
soit leur origine. La vraie frontière n'est pas « YAML contre UI », c'est
`.storage/` contre YAML (§2).

## 2. Ce qui ne sera jamais déclaratif

La configuration d'un HA moderne n'est pas intégralement du YAML : les intégrations
sont des *config flows* créés par l'UI et stockés en JSON dans `/config/.storage/`,
avec leurs identifiants.

| Fichier | Contenu | Pourquoi ça ne peut pas être déclaratif |
|---|---|---|
| `core.config_entries` | les 31 intégrations, avec jetons OAuth / mots de passe | flux interactifs, secrets, UUID générés |
| `core.device_registry` | appareils découverts | identifiants issus de la découverte |
| `core.entity_registry` | les 390 entités, noms personnalisés, `unique_id` → `entity_id` | mapping construit à l'exécution |
| `core.area_registry`, `core.floor_registry`, `core.label_registry` | zones, étages, étiquettes | UUID générés |
| `auth`, `auth_provider.homeassistant`, `person` | comptes, hachages, jetons | secrets |
| `lovelace*` | tableaux de bord en mode *storage* | déclarables **seulement** en renonçant à l'éditeur graphique |
| `input_*` | helpers créés à l'UI | idem |

**On obtiendrait un déploiement déclaratif, pas une configuration déclarative.**
Et `.storage/` restant indispensable et non reproductible, **une sauvegarde reste
obligatoire dans tous les cas** — le dépôt git ne remplace rien.

Cela dit, l'inventaire relativise : 8 intégrations ajoutées à la main et 390
entités, c'est un `.storage/` modeste. Le « non déclarable » est petit ici — mais
le gain côté intégrations l'est aussi. **Le gain est dans le YAML (§1.5), pas dans
les intégrations.**

**Mis à jour le 2026-09-29** : la décision de repartir de zéro change la portée de
cette section. Ce `.storage/` n'est plus quelque chose à migrer, c'est quelque
chose à **refaire** : 8 intégrations à recréer par des flux interactifs, plus ce
que la découverte ramènera seule. Le constat de fond ne bouge pas — une
configuration HA intégralement déclarative reste impossible, et une sauvegarde
reste obligatoire dès que l'instance porte un état réel.

## 3. Les frictions réelles

### 3.1 AirSonos — résolu : à supprimer

**Tranché le 2026-09-28 : l'add-on est inutilisé et sera supprimé, sans
remplacement.**

Matériel Sonos : **Playbar 1ʳᵉ génération** et **Play:3**. Ni l'une ni l'autre ne
supporte **AirPlay 2** (ces modèles sont compatibles S2, mais l'AirPlay 2 exige du
matériel plus récent). AirSonos était donc bien le seul moyen d'envoyer de
l'AirPlay vers ces enceintes — ce n'était pas un doublon.

Mais les usages réels ne passent pas par AirPlay :

- streaming depuis le téléphone → application Sonos / Spotify Connect ;
- streaming depuis Alexa → skill Sonos (cloud).

Aucun des deux n'emprunte AirSonos. Sa suppression est donc sans effet fonctionnel,
et elle retire du dossier une dépendance Node abandonnée en amont (ainsi que la
mise à jour 5.2.3 en attente, désormais sans objet).

**Conséquence : plus aucun bloqueur technique à la migration.**

### 3.2 Réseau — le point de rupture, et la question du VLAN

**Tranché le 2026-09-29 : HA reste sur le lien IoT.** L'en sortir « pour raisons
de sécurité » serait contre-productif, et en natif la question ne se pose même
plus dans ces termes.

#### a. En natif, « quel VLAN pour HA » n'existe plus

`services.home-assistant` n'est pas une entité réseau, c'est un process sur hyper.
Il hérite de **toutes** les pattes de l'hôte : `management` (192.168.10.100),
`br-iot` (192.168.21.241), `vlan100`, `vlan200`, `tailscale0`. Il n'y a plus
d'adresse à choisir — il y a trois réglages à décider :

| Réglage | Mécanisme | Décision |
|---|---|---|
| Sur quoi HA **écoute** | `http.server_host` (liste) | `127.0.0.1` + `192.168.21.241` (voir le piège en d.) |
| Sur quoi HA **découvre** | adaptateurs de l'intégration `network` | `br-iot` seul |
| Ce que HA **peut atteindre** | durcissement systemd (`IPAddressAllow`) | 192.168.21.0/24 + loopback |

Nuance sur le deuxième : dans un HA moderne, la sélection d'adaptateurs vit dans
**`.storage/core.network`** (intégration `network`, réglée par l'UI), pas dans
`configuration.yaml` — c'est donc un geste à faire une fois, et il appartient au
non-déclarable du §2. La formulation « épingler l'interface zeroconf » d'une
révision antérieure laissait croire à une option nix : il n'y en a pas.
À confirmer au moment de la bascule : le sort exact de l'ancienne clé
`zeroconf.default_interface` dans la version de nixpkgs retenue.

#### b. Pourquoi ne pas sortir HA du VLAN IoT

Les 9 intégrations découvertes (§1.3 — `sonos`, `cast`, `lifx`, `tplink` ×2,
`ipp`, `androidtv_remote`, `dlna_dmr`, `thread`) sont **nécessairement sur
vlan21** : la VM n'a que ce lien, et mDNS/SSDP sont du multicast link-local.
Retirer la patte `br-iot`, ce serait donc :

- casser les 9 découvertes d'un coup — et elles ne se recréeraient pas seules ;
- devoir monter un réflecteur mDNS / proxy IGMP sur l'UniFi ;
- ouvrir des règles inter-VLAN explicites, protocole par protocole.

Plus de trous à maintenir, pas moins, pour zéro gain : **HA est par fonction le
service qui doit parler au segment non fiable.** Le VLAN IoT contient les
ampoules et la TV, pas leur contrôleur. Le raisonnement vaut à l'identique pour
l'option C (garder la VM en la déplaçant sur le LAN).

#### c. Le vrai changement de surface est inverse

Aujourd'hui la VM est **confinée** à vlan21. En natif, HA — 220 composants, plus
`alexa_media_player` qui est du code tiers non packagé (§1.2) — tourne sur hyper
avec accès à `management`, `vlan100`, `vlan200` et au tailnet. **C'est le blast
radius de HA qui augmente, pas son exposition aux objets IoT.**

Ce qui le compense, et qui n'existe pas dans la VM :

- **durcissement systemd** — `IPAddressAllow`/`IPAddressDeny` scopés à
  192.168.21.0/24 + loopback redonnent, par cgroup, le confinement que la VM
  donnait par le réseau ;
- **`extraComponents`** — surface Python réduite au strict nécessaire, là où
  l'image HAOS embarque tout.

#### d. Ce que la migration permet de fermer

- **MQTT 1883 sur `br-iot` devient fermable entièrement.** La VM est le *seul*
  client distant du listener (`mosquitto.nix:13` ; z2m et rankoder sont en
  loopback). HA passant en loopback, on retire du segment IoT un service **sans
  TLS, à mot de passe partagé, dont le compte `homeassistant` a l'ACL
  `readwrite #`** — l'essentiel de SEC-3b tombe de lui-même. À vérifier avant de
  le fermer : qu'aucun appareil ne publie en MQTT directement (aucun ESPHome ni
  Tasmota dans l'inventaire — tout passe par z2m).
- **Le port 8123 devient filtrable.** Aujourd'hui il ne l'est pas : `br_netfilter`
  n'est pas chargé sur hyper, donc le trafic bridgé vers la VM ne traverse aucune
  règle — n'importe quel objet de vlan21 atteint la page de login de HA. En natif,
  le port passe par `networking.firewall`, donc par un défaut-deny, et
  `traefik.services.hass.host` devient `127.0.0.1`.
- ⚠️ **Piège à ne pas rater** : ne pas binder sur loopback **seul**. Sonos et
  Cast vont chercher les URL de média/TTS *servies par HA* — si 8123 n'est pas
  joignable depuis vlan21, la TTS et la lecture locale tombent. Il faut garder
  `192.168.21.241:8123` joignable depuis `br-iot` et fixer `internal_url` dessus.
  Le gain net n'est donc pas « 8123 disparaît du VLAN IoT » mais « 8123 est
  exposé là où c'est nécessaire, et nulle part ailleurs ».

#### e. À reprendre lors de la bascule

HA passerait de 192.168.21.181 (VM) à l'hôte :

- `traefik.services.hass.host`, aujourd'hui figé sur l'IP de la VM
  (`hosts/hyper/libvirt.nix`) → `127.0.0.1` ;
- tout appareil configuré avec l'URL de HA, les webhooks externes, les ponts
  HomeKit/Alexa/Google, les intégrations à *callback* ;
- les 3 entrées `mobile_app` (téléphones) et l'intégration `cloud` ;
- `internal_url` / `external_url`.

#### f. Hors périmètre, mais découvert en chemin : SEC-14

L'analyse a mis au jour un trou **indépendant de HA et antérieur à la migration** :
hyper routait entre le VLAN IoT et le LAN sans aucun filtrage. Un objet compromis
sur vlan21 qui prenait 192.168.21.241 comme passerelle atteignait 192.168.10.0/24
en contournant les règles de l'UniFi — vérifié empiriquement, puis **corrigé et
déployé le 2026-09-29** (`hosts/hyper/inter-vlan-firewall.nix`). C'était un enjeu
de sécurité bien plus grand que l'adresse de HA. Voir `docs/security.md`
§ « Routage inter-VLAN filtré » et SEC-14 dans `docs/audit-2026-09.md`.

Conséquence pour la migration : la sonde a confirmé que **mosquitto sur
192.168.21.241:1883 reste joignable depuis vlan21** (c'est de l'INPUT, pas du
forward), donc HA n'est pas impacté — ni aujourd'hui dans la VM, ni demain en
natif.

### 3.3 Chaque déploiement redémarrerait HA

Aujourd'hui `nh os switch` ne touche pas la VM : HA est immunisé contre les
déploiements. En natif, un changement d'unité le redémarre (~20-60 s). Avec le
problème connu d'activation nvidia (nh ne persiste pas la génération en cas
d'erreur), **un switch raté mettrait le chauffage et les lumières par terre.**

C'est le coût le moins visible et le plus concret. Mitigation : `nixos-rebuild
boot` pour les changements risqués, et l'alerte `ServiceDown` existante couvre HA
dès qu'il est derrière Traefik.

### 3.4 Pertes liées au Supervisor

Disparaissent : magasin d'add-ons, CLI `ha`, **mises à jour OTA de l'OS**
(réellement utilisées : HAOS 16.3 → 18.3), page de santé Supervisor.

**Sur les sauvegardes, la nuance est importante** (et corrige une version
antérieure de ce document) : le mécanisme de sauvegarde HA **est** utilisé et
fonctionne (§1.4). Ce qui disparaîtrait précisément :

- l'agent **`hassio.local`** et l'inclusion automatique des add-ons dans l'archive
  — sans Supervisor, il n'y a plus d'add-on à inclure, et les sauvegardes locales
  iraient dans `<configDir>/backups` ;
- rien d'autre : l'intégration **`cloud`** de Nabu Casa fonctionne sans Supervisor,
  donc l'agent **`cloud.cloud`** et la copie hors-site **survivent à la migration**.

La perte n'est donc pas le mécanisme de sauvegarde, mais l'inclusion des add-ons —
ce qui est cohérent avec le fait qu'après migration il n'en resterait plus aucun.

### 3.5 Retard nixpkgs

HA 2026.8.3 dans nixpkgs contre 2026.9.4 en service, Music Assistant 2.9.13 contre
2.10.4 : **un mineur de retard** dans les deux cas. Acceptable — c'est le régime
normal d'un dépôt qui suit nixpkgs, et les bumps sont déjà un geste maîtrisé ici.
À accepter consciemment : les montées de version HA cesseraient d'être un clic pour
devenir un bump nixpkgs.

## 4. Options, réévaluées après inventaire

| | Verdict |
|---|---|
| **A. NixVirt** (domaine libvirt en nix) | **écarté** : déclare le contenant, pas le contenu. Aucun gain sur l'objectif |
| **B. `services.home-assistant` natif** | **retenu** — voir §5 |
| **B2. HA en conteneur** | **écarté après inventaire** : les deux arguments qui le portaient sont tombés (§5) |
| **C. Garder HAOS** + corriger les défauts | repli légitime : sauvegarde + 16 → 4 G, une soirée, zéro risque de migration |

## 5. Pourquoi le natif plutôt que le conteneur

Position inversée par l'inventaire. Les deux arguments qui portaient le conteneur
étaient :

1. *« Music Assistant devient un conteneur de toute façon, donc autant être
   homogène »* → **faux** : `services.music-assistant` existe dans nixpkgs. MA
   devient natif et déclaratif, comme `zigbee2mqtt` et `mosquitto` le sont déjà.
   L'ensemble domotique serait alors entièrement natif et déclaratif.
2. *« HACS impose un `configDir` inscriptible, donc l'image officielle avec toutes
   les intégrations est plus simple »* → **faux** : 3 des 4 dépôts HACS sont dans
   nixpkgs **aux versions exactes** en service, le 4ᵉ est une dérivation courte à
   écrire, et HACS disparaît.

Reste en faveur du conteneur le seul découplage des montées de version — payé par
un modèle de déploiement de plus, alors que tout le reste de la domotique est déjà
en modules NixOS. Le natif gagne aussi `extraComponents` (surface Python réduite au
strict nécessaire) et le durcissement systemd, absent d'un conteneur rootful.

## 6. Procédure de migration

1. **Faire entrer les sauvegardes HA dans restic** (§6 bis) — elles existent déjà
   (§1.4), il manque la copie sur site et la surveillance. C'est le filet de la
   migration.
2. **Supprimer l'add-on AirSonos** (§3.1) — tranché, à faire dès maintenant côté
   HAOS : ça réduit d'autant le périmètre à migrer.
3. **Extraction** : l'archive est un tar contenant `backup.json`,
   `homeassistant.tar.gz` (= `/config`) et un tar par add-on.
   ⚠️ **Vérifié le 2026-09-29 sur la copie locale
   `/mnt/local/ha-backups/ha-7aaaf45a-2026-09-28.tar` : `"protected": true`.**
   Les tarballs internes sont donc **chiffrés** et l'archive est inexploitable
   sans la clé — celle-là même qui est à changer et à ranger dans Vaultwarden
   (§1.4). Trois voies, à trancher :
   a. fournir la clé actuelle et déchiffrer ;
   b. produire depuis HA une sauvegarde **sans mot de passe**, à usage unique ;
   c. **copier `/config` directement depuis la VM** (l'add-on Terminal & SSH est
      encore là, et la VM reste allumée) — la voie la plus directe tant que la VM
      tourne en parallèle.
4. **`/config` → `/var/lib/hass`** (`configDir` par défaut du module) : garder
   `.storage/`, `secrets.yaml`, `automations.yaml`, `scripts.yaml`, `scenes.yaml`,
   `blueprints/`, `www/`. Propriétaire `hass:hass`, `.storage` en 0700.
   **Ne pas reprendre `custom_components/`** : les trois composants passent par
   `customLovelaceModules` / `customComponents`.
5. **`configuration.yaml` en nix**, avec `!include` pour laisser mutables les
   fichiers écrits par l'UI.
   ⚠️ **Le conseil d'origine sur `http` est obsolète depuis HA 2026.8** — voir
   §9. Ne pas déclarer de bloc `http` en nix : il vit désormais dans
   `.storage/http`, l'YAML n'en est plus qu'une migration one-shot à promouvoir
   en 5 minutes, et une promotion ratée est définitive.
   La sélection d'adaptateurs de découverte n'est **pas** du YAML non plus :
   elle se fait à l'UI et atterrit dans `.storage/core.network` (§3.2 a).
6. **Les 10 automatisations écrites à la main** (§1.5) : candidates à passer en nix,
   les rankoder à côté de `medias/rankoder.nix`. Les 7 de l'éditeur graphique
   restent dans `automations.yaml` mutable.
7. **Music Assistant** : `services.music-assistant` + état + `backups.sources` +
   `notify.services`. Puis **recréer à la main l'entrée d'intégration
   `music_assistant`** (elle venait du Supervisor, §1.3). Vérifier le provider
   Sonos à déclarer : la Playbar 1ʳᵉ gén. et les Play:3 sont des modèles anciens
   (compatibles S2), à valider contre les providers Sonos de MA.
8. **Recorder** : ~~à trancher, sans urgence~~ → **tranché le 2026-09-29 :
   PostgreSQL, et tout de suite.** Le seul coût que cette étape listait était
   « une migration d'historique ou sa perte » ; repartir de zéro (§8) l'annule
   entièrement. Et il ne redeviendra jamais nul : différer, c'est choisir de
   payer plus tard ce qui est gratuit maintenant. Détail en §10.
9. **Réseau** (§3.2 e) : `traefik.services.hass.host` → `127.0.0.1`, les URL côté
   appareils, `internal_url`/`external_url`, les 3 `mobile_app`. Puis **fermer 1883
   sur `br-iot`** une fois HA en loopback (§3.2 d) — après avoir confirmé qu'aucun
   appareil ne publie en MQTT directement. Ajouter le durcissement systemd
   (`IPAddressAllow` 192.168.21.0/24 + loopback, §3.2 c).
10. **Jamais les deux *en service* en parallèle** : deux HA sur le même MQTT
    commanderaient les appareils deux fois. Précision apportée le 2026-09-29,
    parce que la VM est justement conservée en parallèle jusqu'au bout (§8) :
    ce qui est interdit, ce n'est pas que les deux **existent**, c'est que les
    deux **possèdent les appareils**. La frontière est le courtier MQTT et les
    intégrations, pas le processus. Tant que l'instance native n'a ni entrée
    `mqtt`, ni route Traefik, ni écoute hors loopback, les deux peuvent tourner
    côte à côte sans risque.
11. **Rollback** : garder le qcow2 au moins un mois, VM définie mais arrêtée.

Corriger au passage `mealie: auth_failed` (§1.3) — indépendant, mais autant le voir
réglé avant de changer de socle.

## 6 bis. Faire entrer les sauvegardes HA dans le pipeline (à déclarer)

> ⚠️ **Section rendue sans objet par la migration en natif** (voir §8, lot B0).
> Tout ce dispositif — jeton agenix dédié, service + timer de récupération par
> l'API, rotation — n'existait que parce que `/config` était enfermé dans une
> VM. En natif, `/var/lib/hass` entre dans restic comme n'importe quel autre
> service. Conservée ci-dessous pour mémoire, et parce qu'elle reste la bonne
> réponse **tant que la VM tourne**.

Indépendant de la migration, et utile même si on garde HAOS.

| Livrable | Contenu |
|---|---|
| Jeton HA dans agenix | un jeton longue durée dédié, en secret agenix (le jeton utilisé pour cet audit est à révoquer) |
| Service + timer nix | tire quotidiennement la dernière sauvegarde via `GET /api/backup/download/<id>?agent_id=hassio.local` vers `/mnt/local/ha-backups/`, avec rotation. L'`id` s'obtient par la commande WebSocket `backup/info` |
| `backups.sources.home-assistant` | `paths = [ "/mnt/local/ha-backups" ]` → entre dans restic, donc USB + Hetzner, donc dans les vérifications et les drills |
| `notify.services` | sur le service de récupération |
| Alerte de fraîcheur | sur `sensor.backup_last_successful_automatic_backup` (intégration `prometheus` de HA, ou vérification côté service de récupération) |
| Clé de chiffrement | à ranger dans Vaultwarden — **sans elle, aucune sauvegarde n'est restaurable** |

Remarque : le proxy Supervisor (`/api/hassio/*`) **refuse les jetons longue durée**
— c'est pourquoi la récupération passe par l'API cœur `backup/download` et par le
WebSocket, et non par `/api/hassio/backups`.

## 7. Recommandation

1. **Immédiat : faire entrer les sauvegardes HA dans le pipeline surveillé**
   (§6 bis). Elles existent et partent déjà hors-site via Nabu Casa (§1.4) : il
   manque une copie sur site hors VM, une alerte de fraîcheur, et la clé de
   chiffrement rangée dans Vaultwarden. C'est important, mais ce n'est pas
   l'urgence absolue que la révision précédente décrivait.
2. **Puis 16 G → 4 G** : ~11 G rendus, le balloon est déjà là, réversible, sans
   rapport avec la question déclarative.
3. **Supprimer AirSonos** (tranché, §3.1) — un add-on de moins à migrer.
4. **Puis migrer en natif** (option B). Plus aucun bloqueur : l'infra y est prête —
   Zigbee2MQTT et
   Mosquitto déjà déclaratifs, pas de passthrough, hôte sur le bon lien, MA et les
   cartes HACS packagés dans nixpkgs.

**Hors périmètre mais prioritaire** : SEC-14 (routage inter-VLAN non filtré sur
hyper, §3.2 f). Il ne dépend pas de la migration, il est vérifié, et il pèse plus
lourd sur la sécurité que tout ce qui précède.

Le compromis de fond, à accepter en conscience : on échangerait « HA immunisé
contre les déploiements » et « MAJ en un clic » contre « HA déployé et versionné
comme le reste ». C'est un choix d'exploitation, pas un détail d'implémentation.

## 8. Découpage en lots (décidé le 2026-09-29)

**Deux décisions structurent ce découpage.** (1) La VM est conservée et reste en
service jusqu'à validation complète ; elle n'est supprimée qu'à la toute fin.
(2) **On repart de zéro** : aucun `/config` n'est repris.

La seconde supprime le lot le plus lourd — et le seul qui était bloqué.

### Lot A — l'instance native, vide · *fait et déployé le 2026-09-29*

`modules/features/home/home-assistant.nix`, importé par hyper. Ce qui rend la
cohabitation sûre (§6.10) :

| Garde-fou | Effet |
|---|---|
| **Aucune intégration `mqtt`** | le courtier reste à la VM ; deux HA dessus commanderaient tout deux fois |
| `http.server_host = [ "127.0.0.1" ]` | aucun appareil ne peut joindre l'instance native |
| Nom d'hôte propre, `ha.hyper.logikdev.fr` | `hass.hyper.logikdev.fr` continue de servir la VM, sans conflit |
| `backups.sources` absent | inutile de secouer une instance sans état réel |

`extraComponents` couvre les 31 entrées du §1.3 — non pour les importer, mais
pour décrire ce qu'on compte **recréer** ; la liste se taille à la baisse dès
qu'un usage est abandonné. Les deux cartes HACS sont déclarées aux versions en
service, et `configWritable` reste à `false`.

Un piège traité au passage : **le module nixpkgs ne crée pas les fichiers que
l'UI écrit**, et un `!include` sur un fichier absent empêche HA de démarrer. Les
trois (`automations.yaml`, `scripts.yaml`, `scenes.yaml`) sont donc amorcés vides
par tmpfiles, qui ne réécrit pas un fichier existant — ce que l'UI y mettra
survit.

Vérifié : les 30 noms de composants existent dans le nixpkgs épinglé
(`availableComponents`, 1481 disponibles, 0 absent), et 8123 n'apparaît pas dans
`allowedTCPPorts`.

Réserve assumée : la découverte zeroconf/SSDP tourne (`default_config`
l'embarque) et fera apparaître des cartes « découvert » pour des appareils que la
VM gère encore. C'est inerte — un flux de découverte ne commande rien tant que
personne ne le confirme — **mais n'en confirmer aucun avant la bascule**.

> ⚠️ **Faux dans les faits, corrigé le 2026-09-29 (§12)** : `default_config`
> n'était pas déclaré dans la configuration, donc **aucune découverte n'a
> tourné** pendant tout le lot A. La réserve ci-dessus était sans objet.

### Lot B — la reconstruction

Plan détaillé arrêté le 2026-09-29, après clôture du lot A.

#### B0. D'abord le filet, avant d'accumuler de l'état irremplaçable

L'onboarding est fait : `.storage/auth` contient déjà un compte qui ne se
reproduit pas. Chaque intégration ajoutée ensuite est un flux interactif qu'il
faudrait refaire à la main. **La sauvegarde doit donc précéder la
reconstruction, pas la suivre.**

```nix
backups.sources.home-assistant = {
  paths = [ "/var/lib/hass" ];
  manageService = false;
  exclude = [ "home-assistant.log*" "tts/" "deps/" ];
};
```

**`manageService = false`, et c'est le passage sur PostgreSQL (§10) qui le
permet.** Tant que l'enregistreur était du SQLite *dans le répertoire de
config*, il fallait arrêter HA autour du passage pour obtenir une base
cohérente — donc un redémarrage nocturne en plus de ceux des déploiements
(§3.3). L'historique étant désormais dans postgres, le répertoire ne contient
plus que des fichiers `.storage/` écrits par renommage atomique : une copie à
chaud les attrape entiers.

**Fait et vérifié le 2026-09-29** : passage forcé réussi, snapshot `a9b97fe6`,
**28 fichiers / 30 Kio**. Cette petitesse est la preuve directe que l'historique
a bien quitté le répertoire.

> **Cela rend le §6 bis sans objet.** Le service de récupération par API
> (`GET /api/backup/download/…`, jeton agenix dédié, rotation) n'existait que
> parce que `/config` était enfermé dans une VM. En natif, `/var/lib/hass` entre
> dans restic comme n'importe quel autre service — donc USB + Hetzner, donc les
> vérifications et les *restore drills*. Un livrable entier disparaît.

#### B1. Ce qui peut être recréé maintenant, et ce qui doit attendre

**Correction d'une formulation antérieure.** J'ai écrit que « la frontière est
le courtier MQTT, pas le processus ». C'est **incomplet** : Sonos, Cast, LIFX,
TP-Link et consorts se commandent *directement en IP*, sans passer par MQTT.
Confirmer un de ces flux de découverte donne donc l'emprise à l'instance native,
indépendamment du courtier. La vraie frontière est **l'emprise sur l'appareil**,
quel qu'en soit le canal.

| Intégration | Maintenant ? | Pourquoi |
|---|---|---|
| `meteo_france`, `open_meteo`, `met`, `sun` | **oui** | données, aucune emprise |
| `radio_browser`, `shopping_list`, `analytics`, `go2rtc` | **oui** | local ou annuaire |
| `google_translate` | **oui** | le service TTS est inerte tant qu'aucun lecteur n'est ciblé |
| `jellyfin` | **oui** | API d'un service ; deux clients ne se gênent pas |
| `mealie` | **oui** | idem — et c'est l'occasion de régler son `auth_failed` (§1.3) |
| `sonos`, `cast`, `dlna_dmr`, `lifx`, `tplink`, `androidtv_remote`, `ipp`, `thread` | **non** | emprise directe en IP. Sans automatisation le risque reste faible, mais l'état et les regroupements (Sonos) se disputent |
| `mqtt` | **non** | double commande de tout le Zigbee (§6.10) |
| `music_assistant` | **non** | deux instances MA pilotant les mêmes Sonos |
| **`cloud` (Nabu Casa)** | **non — à vérifier d'abord** | l'abonnement se lie à une instance. Y connecter le natif risque de **déposséder la VM**, et avec elle sa copie hors-site (§1.4). À confirmer avant toute tentative |
| `mobile_app` | **non** | ré-enregistrer les téléphones les détourne de la VM |
| `alexa_media_player` | **non** | session cloud Amazon ; deux sessions concurrentes se délogent |

Règle pratique : **ne confirmer aucune carte « découvert »** tant que le lot C
n'est pas engagé, même si HA les propose spontanément.

#### B2. Ce que le dépôt suit, et seulement quand l'usage est recréé

Rien de tout ceci n'est à écrire « au cas où » — la décision de repartir de zéro
vaut aussi pour le nix : on ne déclare que ce qui sert.

| Brique | Quand | Note |
|---|---|---|
| `services.music-assistant` | avec `music_assistant`, donc au lot C | `enable`, `package`, `openFirewall`, `extraOptions` ; plus répertoire d'état, `backups.sources`, `notify.services`, route Traefik |
| `alexa_media_player` en `customComponents` | seulement si l'usage Alexa est recréé | `pkgs.buildHomeAssistantComponent` est disponible dans le nixpkgs épinglé (vérifié) |
| Élagage d'`extraComponents` | en continu | la liste vient de l'inventaire de la VM ; tout usage abandonné doit en sortir, c'est le gain de surface du natif (§5) |

#### B3. Les automatisations `rankoder` — *fait le 2026-09-29, voir §11*

Les 5 automatisations du workflow d'approbation (§1.5) pilotent un service
déclaré *dans ce dépôt*, qui publie en MQTT sous le compte `homeassistant`.
Repartir de zéro les fait disparaître, et rankoder publierait ses demandes dans
le vide.

Trois issues : les réécrire en nix à côté de `medias/rankoder.nix` (c'était *le*
gain déclaratif annoncé au §1.5), les recréer à la main dans l'UI, ou assumer de
perdre le workflow d'approbation. **La seule chose à ne pas faire est de
laisser la VM partir sans avoir lu ces automatisations** — c'est la seule
logique de la VM qui appartienne conceptuellement au dépôt.

#### B4. Critères de sortie — ce qui doit être vrai pour engager le lot C

1. `backups.sources.home-assistant` déclaré, **et un passage restic réussi
   constaté** (pas seulement déclaré).
2. Les intégrations « oui » de B1 recréées et chargées sans erreur.
3. ~~Le sort des automatisations `rankoder` tranché (B3).~~ **Fait** (§11) : reprises, triées et réécrites en nix.
4. Le conflit Nabu Casa vérifié, pas supposé.
5. Toujours **aucun client MQTT natif** — la vérification `ss` de ce lot reste
   valable : 2 clients loopback, pas 3.

### Lot C — la bascule

`http.server_host` ouvert sur `192.168.21.241` en plus du loopback (jamais
loopback seul, §3.2 d — **et à régler dans l'UI, pas en nix**, cf. §9),
`traefik.services.hass.host` → `127.0.0.1` et retrait de la route `ha`, création
de l'entrée `mqtt` côté natif **et retrait côté VM dans le même geste**, reprise
des URL côté appareils et des `mobile_app`.

Deux gestes à ne pas oublier au même moment :

- ajouter **`home-assistant.service`** à la liste `expected` de
  `monitoring/mqtt-clients.nix` (MON-11). C'est là que ce relevé vaut le plus :
  une fois le natif propriétaire du courtier, un décrochage silencieux coûterait
  exactement ce qu'a coûté P0-9 ;
- `backups.sources.home-assistant` est **déjà en place** depuis B0, rien à faire. C'est ici, et seulement ici, que la propriété
des appareils change de main.

### Lot D — le retrait

Fermeture de `1883` sur `br-iot` (vérifié le 2026-09-29 : la VM est le **seul**
client distant du courtier, cf. SEC-3b), arrêt de la VM, conservation du qcow2 au
moins un mois, puis suppression.

### Ce que la décision « repartir de zéro » a retiré du dossier

- **L'archive chiffrée n'est plus un blocage.** `/mnt/local/ha-backups/…tar` est
  `"protected": true` (§6.3) ; on ne l'ouvre pas, donc la clé n'est plus sur le
  chemin critique. Elle reste à changer et à ranger dans Vaultwarden — mais
  comme hygiène, plus comme dépendance.
- **P0-9 cesse d'être bloquant.** HA n'a plus de connexion MQTT depuis le
  2026-09-27 (`docs/audit-2026-09.md`). Tant qu'on migrait, il fallait le
  réparer pour pouvoir tester la bascule. En repartant de zéro, c'est l'instance
  native qui prendra le courtier, et l'état MQTT de la VM n'a plus d'importance
  — sauf si le Zigbee doit continuer à marcher d'ici là, ce qui reste à trancher.

## 9. Le piège `http` de HA 2026.8 (vécu le 2026-09-29)

**Ne pas déclarer de bloc `http` dans `services.home-assistant.config`.** C'est
contre-intuitif — c'est exactement ce que le §6.5 recommandait — mais le
mécanisme a changé et la recommandation est devenue un piège fermé.

### Ce qui se passe réellement

Depuis HA 2026.8, la configuration `http` vit dans `.storage/http` sous la forme
d'un couple `stable` / `pending`, et l'YAML n'en est plus qu'une **migration
one-shot** :

1. au premier démarrage, l'YAML est importé comme `pending`, l'ancienne
   configuration restant `stable` ;
2. `pending` doit être **promue dans les 5 minutes** via l'API WebSocket — donc
   depuis une session **authentifiée** ;
3. sans promotion, HA revient à `stable`, redémarre, et marque la pending
   `error: not_promoted`. La source est explicite : *« kept for inspection but
   never applied again »* ;
4. `yaml_migration_done` est alors posé : **l'YAML n'est plus jamais relu**.

### Pourquoi c'est un piège fermé sur une instance neuve derrière un proxy

HA renvoie **400** à toute requête portant un `X-Forwarded-For` venant d'un
proxy non déclaré — et Traefik en pose toujours un. Donc : pas de reverse proxy
fiable → pas d'authentification possible → pas de promotion → révocation au bout
de 5 minutes → configuration définitivement écartée. Le serpent se mord la queue.

### Le faux positif qui l'a masqué

Une vérification faite ~40 s après le démarrage a renvoyé **302** et a été
comptée comme un succès. C'en était un — mais seulement pendant la fenêtre de
5 minutes. Le `400` n'est apparu qu'après la révocation automatique, au
redémarrage suivant. **Leçon de méthode : sur un HA fraîchement démarré, une
réponse correcte ne prouve rien tant que la fenêtre de promotion n'est pas
passée.**

### La marche à suivre

1. **Aucun bloc `http` en nix.** HA démarre sur ses défauts : bind `0.0.0.0:8123`,
   pas de confiance proxy. Ce n'est pas une ouverture réseau — 8123 n'est pas
   dans `allowedTCPPorts`, donc le port est injoignable depuis toutes les
   interfaces (vérifié depuis le LAN, le tailnet et le VLAN IoT ; sonde de
   contrôle sur 1883 pour prouver que le test discrimine).
2. **Onboarding hors proxy** : `ssh -L 8123:127.0.0.1:8123 hyper`, puis
   `http://localhost:8123`. Pas de `X-Forwarded-For`, donc pas de 400.
3. **Puis régler le reverse proxy dans l'UI** (Paramètres → Système → Réseau),
   où la promotion se fait proprement depuis une session authentifiée. C'est à
   ce moment que `ha.hyper.logikdev.fr` cesse de renvoyer 400.
4. Purger `.storage/http` si une pending a déjà échoué : sans ça, la
   configuration reste marquée `not_promoted` pour toujours.

### Résultat (2026-09-29)

La marche à suivre a été appliquée et fonctionne. Après onboarding hors proxy et
réglage du reverse proxy dans l'UI, `.storage/http` contient :

```
stable : use_x_forwarded_for=True, trusted_proxies=['127.0.0.1/32'], error=None
pending: None
```

**`pending: None` est le point à vérifier** : rien en attente, donc aucune
minuterie de révocation. C'est la différence entre un réglage promu par l'UI et
une migration YAML non confirmée.

Un dernier écueil, sans rapport avec HA : la **première émission ACME** de la
route `ha` a échoué (`403 :: No TXT record found at _acme-challenge.ha…`) et
Traefik n'a pas réessayé seul. Un `systemctl restart traefik` a suffi. À retenir
pour toute nouvelle route — et à ne pas masquer avec `curl -k`
(cf. `docs/networking.md` § Traefik).

**État final : `ha.hyper.logikdev.fr` → 200, certificat valide.** La VM répond
toujours sur `hass.hyper.logikdev.fr` → 200. Le courtier MQTT n'a toujours que
ses deux clients loopback : l'instance native n'a pas touché aux appareils.

## 10. L'enregistreur sur PostgreSQL (tranché et fait le 2026-09-29)

Question posée en cours de lot B : *ne serait-il pas plus intéressant de se
brancher sur postgres tout de suite ?* Oui — et c'est le seul moment où ça ne
coûte rien.

### Pourquoi maintenant et pas plus tard

Le §6.8 différait ce choix pour une seule raison : « au prix d'une migration
d'historique ou de sa perte ». La décision de repartir de zéro supprime ce coût
**entièrement**, et c'est une fenêtre qui se referme : dans six mois, la même
décision coûtera l'historique accumulé. L'arbitrage est unilatéral aujourd'hui,
il ne le sera plus jamais.

### Ce que ça apporte

- **HA entre dans le PITR pgBackRest.** La stanza est unique (`default`) et
  porte le **cluster**, pas une base : `hass` vit dans
  `/var/lib/postgresql/16` avec authelia, immich, vaultwarden et les \*arr, donc
  elle est couverte par l'archivage WAL dès sa création et par la prochaine
  sauvegarde complète — sur les **deux** dépôts, USB et Hetzner hors-site.
  C'est plus fort qu'un instantané restic nocturne d'un fichier SQLite.
- **Plus de redémarrage nocturne de HA** : voir B0. Le répertoire de config
  devient petit et stable, donc `manageService = false`.
- **Pas de secret à gérer** : connexion en peer par la socket Unix, comme
  n8n/vaultwarden/authelia. `ensureDBOwnership` impose base == rôle, d'où `hass`
  et non `homeassistant`.

### Les trois vérifications faites avant d'écrire la ligne

Après le piège du §9, rien n'a été supposé :

| Question | Réponse |
|---|---|
| `recorder` a-t-il le mécanisme `pending`/`promote` de `http` ? | **non** — propre à `http`, `recorder` reste du YAML classique |
| Faut-il ordonner le service après postgres ? | **non** — le module nixpkgs pose déjà `after = [ … "postgresql.target" ]` |
| Le pilote est-il disponible ? | oui — `psycopg2` 2.9.12, ajouté via `extraPackages` |

### Preuve que l'enregistreur écrit bien dans postgres

Le premier test choisi — compter les lignes de `states` à 20 s d'intervalle —
**n'a rien prouvé** : une instance vide n'a presque aucune entité qui change,
donc l'absence de progression était attendue et non concluante. Les preuves
retenues :

- `recorder_runs` contient une exécution **vivante** (`end` NULL) démarrée à
  l'activation ;
- `pg_stat_database` compte 1406 insertions sur la base `hass` ;
- **aucun fichier SQLite** ne subsiste dans `/var/lib/hass`.

### Reste à décider

`purge_keep_days` est laissé au défaut de HA (10 jours), faute de base pour
choisir autre chose. C'est le bouton à tourner si l'historique doit durer plus
longtemps — en gardant à l'esprit que ça pèse aussi sur les WAL, donc sur
pgBackRest.

## 11. Reprise des automatisations : six défauts, pas une traduction

Les YAML de la VM ont été récupérés le 2026-09-29 avant son arrêt (archive de
lecture dans `docs/legacy-haos/`). L'intention était de traduire ; la réalité a
été de **trier**. Ce qui suit justifie après coup la décision de repartir de
zéro : une migration mécanique aurait recopié ces défauts sans les voir.

### Ce qui a été repris

| Famille | Repris | Destination |
|---|---|---|
| **rankoder** | 3 automatisations + 8 capteurs MQTT | `medias/rankoder.nix` |
| **arrosage** | 3 automatisations + `binary_sensor.il_va_pleuvoir` | `home/home-assistant-arrosage.nix` |

Écartés sciemment : musique (5 automatisations, 11 scripts), médias (2 + le
script `notifier`), mouvement chambre des enfants, `script.dejeuner`, capteurs
Mealie, `input_boolean.poubelles_sorties`.

### Les six défauts

1. **Faux doublon `rankoder_approval_request`.** Deux entrées de même `id` — en
   réalité une **ancre YAML** (`&id001` / `*id001`), le même nœud émis deux fois
   par le sérialiseur. Déclaré une seule fois en nix.

2. **`rankoder_deliver_deferred` était du code mort.** L'automatisation et son
   script se conditionnaient sur `input_text.rankoder_pending_id` — et
   `rankoder_pending_title`, `rankoder_pending_msg`. Recherche exhaustive dans
   `automations.yaml`, `scripts.yaml` et `configuration.yaml` : ces helpers sont
   **lus quatre fois, écrits zéro fois**. La remise différée à 09:00 ne pouvait
   pas se déclencher. Non repris — à réimplémenter proprement si le besoin
   existe encore.

3. **L'alerte d'échec de transcodage ne pouvait pas charger.** Son déclencheur
   imbriquait le topic sous une clé `options` que le schéma MQTT ne connaît pas,
   alors que `topic` y est obligatoire :

   ```yaml
   triggers:
   - trigger: mqtt
     options:                    # ← invalide
       topic: rankoder/failure
   ```

   Configuration invalide, donc automatisation non chargée : **les échecs de
   transcodage étaient silencieux**. Corrigé.

4. **Cible de notification incohérente.** `rankoder_approval_response` effaçait
   la notification via `notify.iphone_de_cedric`, sans le préfixe `mobile_app_`
   utilisé partout ailleurs. Aligné.

5. **`templates.yaml` ne parsait pas — et ça cassait l'arrosage.**
   `- binary_sensor:` était indenté à 2 colonnes au lieu de 0 (ligne 24), ce qui
   rend le document invalide. Donc `binary_sensor.il_va_pleuvoir` n'existait
   pas. Or les deux automatisations d'arrosage s'en servent **comme condition** —
   l'une exige `off` pour arroser, l'autre `on` pour prévenir du saut. Une entité
   absente ne satisfait ni l'une ni l'autre : **l'arrosage ne démarrait jamais et
   l'alerte ne partait jamais.**

   Réserve honnête : impossible de distinguer « cassé dans la VM » de « abîmé au
   copier-coller ». Le fichier est archivé tel qu'il a été fourni.

6. **Variables calculées jamais utilisées** : `pluie_prevue` et
   `precipitation_ml` dans deux automatisations d'arrosage, la condition passant
   par le `binary_sensor`. Supprimées.

### Le mécanisme de déclaration

`modules/features/home/home-assistant-automations.nix` ajoute une option
`homeAssistant.automations`, rendue dans la clé **`automation nix:`** —
distincte de `automation:` (`!include automations.yaml`) que l'UI écrit et qui
reste mutable. HA fusionne les deux : `cv.domain_key` découpe la clé sur le
premier espace et `extract_domain_configs` collecte toutes les clés du domaine
(vérifié dans la source 2026.8.3). **Déclarer ne retire donc rien à l'UI.**

Le but n'est pas de tout déclarer : c'est de rapprocher du dépôt les
automatisations qui pilotent un service que le dépôt déclare déjà — ce qui était
l'argument du §1.5.

### État au 2026-09-29

Déployé et persisté (génération 512). Les 6 automatisations sont enregistrées,
`binary_sensor.il_va_pleuvoir` existe, 0 unité en échec. Les deux seules erreurs
au journal sont `mqtt_not_setup_cannot_subscribe` sur les déclencheurs MQTT de
rankoder — **attendu**, l'intégration MQTT n'étant pas encore configurée.

Dépendances à recréer côté UI pour que tout s'anime :

| Dépendance | Débloque | État |
|---|---|---|
| Intégration **MQTT** | les 3 automatisations rankoder, les 8 capteurs, la vanne via Zigbee2MQTT | **faite le 2026-09-29** |
| Intégration **meteo_france** | `binary_sensor.il_va_pleuvoir`, donc les conditions d'arrosage | à faire |
| Enregistrement **`mobile_app`** du téléphone | toutes les notifications | à faire |

### MQTT : ce que la connexion a effectivement débloqué (2026-09-29)

L'instance native est devenue cliente du courtier, et **la découverte a fait le
reste** sans intervention :

- les **8 capteurs `rankoder/status`** déclarés en nix sont apparus ;
- toute la **vanne Sonoff** est remontée par Zigbee2MQTT — 15 entités, dont
  **`switch.vanne_sonoff` sous exactement l'id que les automatisations
  ciblent**, ce qui valide la reprise sans retouche ;
- les entités du pont zigbee2mqtt (version, log level, permit join, état de
  connexion) ;
- les erreurs `mqtt_not_setup_cannot_subscribe` ont disparu du journal.

**MON-11 fermé dans la foulée** : `home-assistant.service` ajouté à la liste
`expected` du relevé (génération 513). Prometheus suit les 3 clients, les deux
règles sont `inactive`/`health=ok`. C'est pour cette ligne que le module
existait — le natif porte désormais tout le Zigbee, un décrochage silencieux
coûterait ce qu'a coûté P0-9.

## 12. `extraComponents` ne charge rien (vécu le 2026-09-29)

Symptôme : l'application compagnon répondait **« le composant mobile_app n'est
pas chargé »**, et aucune trace d'enregistrement n'atteignait HA.

### La confusion

`services.home-assistant.extraComponents` n'ajoute que les **dépendances
Python au paquet**. Elle ne dit pas à HA de charger quoi que ce soit. HA charge
une intégration dans deux cas seulement : elle est déclarée comme clé dans
`configuration.yaml`, ou elle possède une **entrée de configuration** dans
`.storage`.

`mobile_app` ne peut pas avoir d'entrée de configuration avant d'être chargée —
c'est l'enregistrement de l'app qui la crée. Il fallait donc la déclarer. Elle
l'était dans le `configuration.yaml` de la VM, via `default_config:`, que j'ai
omis en réécrivant la configuration en nix.

### Pourquoi la panne était peu lisible

Les intégrations possédant une entrée `.storage` — celles de l'onboarding —
fonctionnaient normalement. L'UI avait l'air saine. Ce qui manquait était
invisible tant qu'on ne le cherchait pas : `mobile_app`, mais aussi
`zeroconf`/`ssdp`/`dhcp`, `webhook`, `history`, `logbook`, `media_source`.

**Correction d'une affirmation antérieure** : le §8 (lot A) et les commentaires
du module annonçaient que « la découverte zeroconf/SSDP tourne quand même,
`default_config` l'embarque ». C'était faux dans les faits — `default_config`
n'était pas chargé, donc **aucune découverte n'a tourné** entre le 2026-09-29
18:10 et 23:35. La réserve sur les cartes « découvert » à ne pas confirmer était
sans objet pendant cette fenêtre.

### Deux détails qui coûtent du temps

- **Un `nixos-rebuild switch` ne suffit pas** : l'activation fait un *reload* de
  `home-assistant.service`, et un reload ne charge pas une intégration
  nouvellement déclarée — il ne recharge que les domaines rechargeables
  (automations, scripts, template, entités MQTT). Il faut un
  `systemctl restart home-assistant`.
- **Test décisif de chargement** : `GET /api/mobile_app/registrations`. Un
  **404** signifie composant absent ; **405** (méthode non permise) ou **401**
  signifient que la route existe, donc que le composant est chargé. Plus fiable
  que de chercher « Setting up … » dans le journal, que HA n'émet pas au niveau
  INFO par défaut.

### Effet de bord assumé

`default_config` active la découverte USB, qui trouve le dongle Zigbee et tente
de proposer **ZHA**. Le module n'étant pas packagé — c'est zigbee2mqtt qui
possède le dongle — le journal montre `No module named 'zha'` à chaque
démarrage. C'est cosmétique : un flux de découverte qui échoue à se charger, pas
un service en panne. Se tait définitivement en **ignorant** la carte « découvert »
correspondante dans l'UI.

## Références internes

- `modules/hosts/hyper/libvirt.nix` (domaine impératif, `traefik.services.hass`)
- `modules/features/medias/rankoder.nix` (service piloté par 5 automatisations HA)
- `modules/features/networking/mqtt/zigbee2mqtt.nix` (gabarit : domotique déjà déclarative)
- `docs/resource-control-plan.md` §2.5 et C2 (sauvegardes, dimensionnement VM)
