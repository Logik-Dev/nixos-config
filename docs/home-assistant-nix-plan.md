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
   `homeassistant.tar.gz` (= `/config`) et un tar par add-on (chiffrement possible :
   conserver la clé).
4. **`/config` → `/var/lib/hass`** (`configDir` par défaut du module) : garder
   `.storage/`, `secrets.yaml`, `automations.yaml`, `scripts.yaml`, `scenes.yaml`,
   `blueprints/`, `www/`. Propriétaire `hass:hass`, `.storage` en 0700.
   **Ne pas reprendre `custom_components/`** : les trois composants passent par
   `customLovelaceModules` / `customComponents`.
5. **`configuration.yaml` en nix**, avec `!include` pour laisser mutables les
   fichiers écrits par l'UI. Ajouter `http.use_x_forwarded_for` + `trusted_proxies`
   pour Traefik, et `http.server_host = [ 127.0.0.1, 192.168.21.241 ]` (§3.2 a/d).
   La sélection d'adaptateurs de découverte n'est **pas** du YAML : elle se fait à
   l'UI et atterrit dans `.storage/core.network` (§3.2 a).
6. **Les 10 automatisations écrites à la main** (§1.5) : candidates à passer en nix,
   les rankoder à côté de `medias/rankoder.nix`. Les 7 de l'éditeur graphique
   restent dans `automations.yaml` mutable.
7. **Music Assistant** : `services.music-assistant` + état + `backups.sources` +
   `notify.services`. Puis **recréer à la main l'entrée d'intégration
   `music_assistant`** (elle venait du Supervisor, §1.3). Vérifier le provider
   Sonos à déclarer : la Playbar 1ʳᵉ gén. et les Play:3 sont des modèles anciens
   (compatibles S2), à valider contre les providers Sonos de MA.
8. **Recorder** : garder SQLite (reprise de l'historique) ou basculer sur
   PostgreSQL — ce qui ferait entrer HA dans le PITR pgBackRest, au prix d'une
   migration d'historique ou de sa perte. À trancher, sans urgence.
9. **Réseau** (§3.2 e) : `traefik.services.hass.host` → `127.0.0.1`, les URL côté
   appareils, `internal_url`/`external_url`, les 3 `mobile_app`. Puis **fermer 1883
   sur `br-iot`** une fois HA en loopback (§3.2 d) — après avoir confirmé qu'aucun
   appareil ne publie en MQTT directement. Ajouter le durcissement systemd
   (`IPAddressAllow` 192.168.21.0/24 + loopback, §3.2 c).
10. **Jamais les deux en parallèle** : deux HA sur le même MQTT commanderaient les
    appareils deux fois.
11. **Rollback** : garder le qcow2 au moins un mois, VM définie mais arrêtée.

Corriger au passage `mealie: auth_failed` (§1.3) — indépendant, mais autant le voir
réglé avant de changer de socle.

## 6 bis. Faire entrer les sauvegardes HA dans le pipeline (à déclarer)

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

## Références internes

- `modules/hosts/hyper/libvirt.nix` (domaine impératif, `traefik.services.hass`)
- `modules/features/medias/rankoder.nix` (service piloté par 5 automatisations HA)
- `modules/features/networking/mqtt/zigbee2mqtt.nix` (gabarit : domotique déjà déclarative)
- `docs/resource-control-plan.md` §2.5 et C2 (sauvegardes, dimensionnement VM)
