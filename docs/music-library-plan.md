# Plan — bibliothèque musicale locale (Lidarr, Soulseek, beets, Navidrome)

> Statut : **WP0 fait** (secret `slskd.env` créé + décisions actées, §0.2) —
> aucun module écrit, rien déployé.
> Date : 2026-09-30 · **révision 3** (décisions actées : §0.2).
> Portée : `hyper` (greffe sur les stacks médias et torrent existantes).
> **Décision cadre : le classique ne passe pas par Lidarr.** Deux pipelines
> d'acquisition/import distincts (mainstream automatisé, classique curaté par
> beets), une seule bibliothèque servie, un seul serveur d'écoute.

## 0. Origine

Question de départ : « un équivalent Radarr/Sonarr pour la musique, sachant que
le classique va poser problème ». Le plan ci-dessous corrige et complète une
première réponse LLM ; les écarts relevés sont consignés en §7 (Écarté) et §6
(Pièges), avec les versions **relevées le 2026-09-30 dans le nixpkgs épinglé du
dépôt** — à revérifier après un bump.

### 0.1 Corrections apportées en r2

| # | Point r1 | Correction |
|---|---|---|
| R1 | M4 : règle de chemin `albumtype:classical:` | **Règle morte** : beets ne remplit `albumtype` qu'avec le *type primaire* MusicBrainz, et « classical » n'existe pas dans cette énumération (Album/Single/EP/Broadcast/Other + secondaires Compilation/Soundtrack/Live…). Tout serait parti dans `populaire/`. Corrigé en profondeur : **beets devient une bibliothèque classique dédiée** (M4), donc plus aucun sélecteur à écrire — Lidarr est seul à importer `populaire/` |
| R2 | M4 : arborescence `Compositeur/Œuvre/…` | **Piège non vu en r1** : les formats de chemin sont évalués **par item**, donc un récital ou un coffret multi-œuvres verrait ses pistes **éclatées** dans autant de répertoires. L'album cesse d'être une unité sur disque pour un gain nul (aucun client ne navigue par œuvre). L'album redevient l'unité ; la hiérarchie vit **dans les tags** |
| R3 | M4 : `parentwork` supposé actif | `parentwork.auto` vaut **`no`** par défaut (`force` aussi) : sans `auto: yes` les champs sont vides au calcul du chemin *et* au moment du tag. Les `import_stages` tournant avant `manipulate_files`, `auto: yes` suffit — et ne coûte sa requête MB/s **que** sur le classique grâce à R1 |
| R4 | M5 : « MA tourne dans la VM HA » | **Prémisse périmée le jour même** : VM HAOS arrêtée, route Traefik `hass` retirée le 2026-09-30 (`modules/hosts/hyper/libvirt.nix:5-7`), et `services.music-assistant` **pas encore déclaré** (`home-assistant.nix:31`). M5 devient « redéployer MA en natif » |
| R5 | M4 : sauvegarde beets | `backups.sources` a `manageService = true` par **défaut** (`storage/restic.nix:137-141`) et génère `systemctl stop <source>.service` (`:85-88`) → une source `beets` ferait **échouer le job** sur une unité inexistante. `manageService = false` obligatoire |
| R6 | M3 : répertoires de transfert slskd | `ReadWritePaths` **ne crée rien** et slskd tourne `slskd:slskd` → règles `tmpfiles` + `group = "media"` + UMask 0002, sinon beets ne peut pas lire derrière |
| R7 | M3 : secret slskd | Il faut **aussi** `SLSKD_USERNAME`/`SLSKD_PASSWORD` (WebUI), pas seulement les `SLSKD_SLSK_*` (réseau) |
| R8 | M3 : `netns.services` non gardé | À envelopper dans `lib.mkIf config.vpn.airvpn.enable` comme `qbittorrent.nix:36` / `prowlarr.nix:38`, sinon unité fantôme (FAC-5) |
| R9 | M2 : « dataset reconstruit 2×/semaine » | C'est la cadence de **build amont**. Dans le conteneur le rafraîchissement est **opt-in** (`-dataset-refresh`, off par défaut) et le repli live aussi (`-fallback`, qui **exige** `-contact`) |
| R10 | P7 : durcissement slskd × netns | **Relativisé** : systemd applique `NetworkNamespacePath` avant l'userns, le combo est prévu pour marcher. On garde la validation empirique, on retire le conseil de relâcher `PrivateUsers` |
| R11 | P8 : « 2× l'espace pendant le seed » | À scinder : le doublement est **transitoire pour toute source** (découpage + `copy: yes`), et **permanent seulement pendant un seed** torrent. Soulseek ne seede pas |

### 0.2 Décisions actées (fin WP0, 2026-09-30)

| Sujet | Valeur |
|---|---|
| Port AirVPN slskd | **54500** (public = local, à demander dans la Client Area) |
| Provider métadonnées | `LMP_DATASET_REFRESH=72h` + `LMP_FALLBACK=true` + `LMP_CONTACT=${constants.users.logikdev.email}` |
| Sonde VPN (P6) | étendue : `wg0:47594` (qBittorrent) **et** présence de `:54500` (slskd — il ne se lie pas à `wg0`, le motif `wg0:<port>` ne matcherait jamais) |
| Navidrome | `notify.services` + `backups.sources.navidrome` (`exclude = [ "/var/lib/navidrome/cache" ]`) — absents de r2 |
| Dossier legacy | `/mnt/storage/medias/music` (vide, root:media) supprimé au WP1 |
| Secret slskd | `secrets/hosts/hyper/slskd.env.age` créé + rekeyé ; WebUI `slskd` + mot de passe généré ; `SLSKD_SLSK_*` = `CHANGEME` à remplacer avant WP2 |

## 1. Existant (vérifié dans le dépôt)

| Brique | État | Fichier |
|---|---|---|
| qBittorrent natif, netns AirVPN | **déjà là** | `modules/features/downloads/qbittorrent.nix` |
| WireGuard + namespace `vpn` fail-closed | **déjà là** | `modules/features/downloads/vpn.nix` |
| cross-seed + freeleech-farmer | **déjà là** | `modules/features/downloads/{cross-seed,freeleech-farmer}.nix` |
| Prowlarr (dans le netns) | **déjà là** | `modules/features/medias/prowlarr.nix:24` |
| SABnzbd | **déjà là** | `modules/features/medias/sabnzbd.nix` |
| Pattern servarr (Postgres + env) | **déjà là** | `modules/features/medias/lib/_servarr.nix` |
| UMask 0002 + groupe `media` | **déjà là** | `modules/features/medias/lib/_media-service.nix` |
| Jellyfin (vidéo) | **déjà là** | `modules/features/medias/jellyfin.nix` |
| Home Assistant natif | **déjà là** (`ha.*`) | `modules/features/home/home-assistant.nix` |
| Music Assistant → Sonos/Alexa | **à redéployer** : VM HAOS arrêtée et route `hass` retirée le 2026-09-30, `services.music-assistant` pas encore déclaré | `libvirt.nix:5-7`, `home-assistant.nix:31`, `docs/music-home.md` |
| **Musique : rien** | — | aucune racine `medias/musique`, aucun serveur audio |

Conséquence directe : **aucun client torrent ni VPN à installer**, et surtout
**pas de VPN-Confinement** — le dépôt a sa propre implémentation netns
(`vpn.airvpn.netns.services`), en ajouter une seconde casserait le routage.

## 2. Pourquoi le classique casse le modèle *arr

1. **Mauvais modèle de données.** Lidarr modélise `artiste → album`. Le classique
   est `compositeur → œuvre → enregistrement (chef, orchestre, solistes, année)`.
   Sur MusicBrainz l'« artiste » d'une parution classique est tantôt le
   compositeur, tantôt l'interprète, tantôt *Various Artists*.
2. **Surveiller un compositeur est ingérable.** « Bach » = des milliers de
   release groups. Surveiller un chef fonctionne mieux mais on ne raisonne plus
   par œuvre.
3. **La notion d'upgrade qualité n'a pas de sens.** Deux enregistrements
   différents de la 5ᵉ ne sont pas deux qualités d'un même objet : le cœur de
   l'automatisation *arr (cutoff + upgrade) est inopérant.
4. **Trous MusicBrainz.** Beaucoup de pressages anciens/épuisés n'y sont pas du
   tout → Lidarr ne peut pas importer. beets sait (`--noautotag`).
5. **Titres non parsables.** `Symphony No. 5 in C minor, Op. 67: I. Allegro con
   brio` contre `Beethoven - Symphonie 5 - 1. Allegro` : le matching flou de
   Lidarr échoue.
6. **`image + .cue`.** Très fréquent en classique (un gros FLAC + un cue) :
   Lidarr ne sait pas importer, il faut découper avant.

C'est le point 4 qui tranche : même en « mode curation, monitoring None »,
Lidarr reste incapable d'importer une part significative du corpus classique.
D'où la décision cadre.

## 3. Décisions

| Question | Décision | Raison |
|---|---|---|
| Un ou deux pipelines ? | **Deux** : Lidarr (mainstream), beets (classique) | §2.4 — Lidarr ne peut pas importer hors-MusicBrainz |
| Métadonnées Lidarr | **Provider auto-hébergé** dès le départ | Le serveur cloud casse régulièrement l'ajout d'artistes |
| Source principale classique | **Soulseek (slskd)** | Coffrets complets FLAC+cue+log+scans, recherche par nom de fichier = recherche « œuvre + interprète » |
| Source secondaire | Usenet (existant) + achats (Presto, eClassical, Qobuz, labels) | En classique on achète *un* enregistrement précis, pas du volume |
| RuTracker | **Optionnel, manuel, en dernier** | Cloudflare + captcha + FlareSolverr inopérant au login (§6) |
| Tagging classique | **beets** + plugin `parentwork` | Stock, headless, scriptable ; Picard est une GUI (§7) |
| Serveur d'écoute | **Navidrome** à côté de Jellyfin | Rôles multi-valués (compositeur/chef/interprète) depuis 0.55 ; provider Subsonic pour Music Assistant |
| Authelia sur Navidrome | **Non** | Clients natifs + provider MA : même raison que Jellyfin |
| Plugins Lidarr (Tubifarry…) | **Non** | La version épinglée est antérieure au support des plugins (§6) |

## 4. Architecture visée

```
                      ┌─ netns vpn (AirVPN, fail-closed) ─────────────┐
                      │  Prowlarr ──┐                                 │
                      │  qBittorrent│  slskd (Soulseek)   port fwd #2 │
                      └─────────────┼─────────────────────┬───────────┘
                                    │ veth 10.200.0.0/30  │
   SABnzbd (hôte) ──────────────────┤                     │
                                    ▼                     ▼
                               Lidarr (hôte, :8686)   downloads/slskd
                                    │                     │
             metadata-provider ◄────┤                     │
             (conteneur, local)     │                     │
                                    ▼                     ▼
                /mnt/storage/medias/musique/populaire   (classique : beets)
                                    │                     │
                                    └────────┬────────────┘
                                             ▼
                                    Navidrome (:4533)
                                             │
                            ┌────────────────┴───────────────┐
                            ▼                                ▼
                  Music Assistant (natif, lot C)     clients Subsonic
                  → Sonos / Alexa                    (Symfonium, etc.)
```

Racines : `/mnt/storage/medias/musique/{populaire,classique}`. Deux
sous-arborescences, **une seule** `MusicFolder` Navidrome (le filtrage se fait
par tag/dossier, pas par bibliothèque).

## 5. Chantiers

### M1 — Lidarr (mainstream)

Calque exact de `radarr.nix` : le module nixpkgs est un **servarr**
(`services/misc/servarr/lidarr.nix`, partage `settings-options.nix` avec
radarr/sonarr), donc `lib/_servarr.nix` marche tel quel (`LIDARR__POSTGRES__*`).

Nouveau fichier `modules/features/medias/lidarr.nix` :

```nix
imports = [
  (import ./lib/_servarr.nix { inherit pkgs; } {
    app = "lidarr"; mainDb = "lidarr-main"; logDb = "lidarr-logs";
  })
  (import ./lib/_media-service.nix { app = "lidarr"; })
];

traefik.services.lidarr = {
  port = 8686; enableAuthelia = true;
  category = "Médias"; icon = "di:lidarr";
};

services.lidarr = { enable = true; dataDir = "/mnt/ultra/lidarr"; };
notify.services = [ "lidarr" ];

backups.sources.lidarr = {
  paths = [ config.services.lidarr.dataDir ];
  exclude = [                                   # cf. radarr : cache régénérable
    "${config.services.lidarr.dataDir}/MediaCover"
    "${config.services.lidarr.dataDir}/logs"
  ];
};
```

Touchpoints obligatoires ailleurs :

1. `modules/features/medias/default.nix:26` — ajouter
   `ALTER DATABASE "lidarr-main" OWNER TO lidarr;` et la ligne `-logs`.
   **Sans ça Lidarr ne peut pas créer ses tables** (PG15+ exige que le rôle
   possède la base), c'est le piège que ce fichier documente déjà.
2. `modules/features/medias/default.nix:39` — ajouter `lidarr` aux `imports`.
3. `modules/features/downloads/vpn.nix:110` — ajouter `8686` à `hostPorts`
   (défaut `[8989 7878]`) : Prowlarr est **dans** le netns et pousse ses
   indexeurs vers Lidarr par app-sync, via la veth.
4. Racine média : `d /mnt/storage/medias/musique 2775 logikdev media` dans les
   `systemd.tmpfiles.rules` du module `seedbox`.

Porte de sortie : un artiste ajouté, un album grabbé par SABnzbd **et** par
qBittorrent, importé en hardlink dans `musique/populaire`.

### M2 — Serveur de métadonnées auto-hébergé

[`NC1107/lidarr-metadata-provider`](https://github.com/NC1107/lidarr-metadata-provider) :
dataset construit depuis les dumps CC0 MusicBrainz, publié **deux fois par
semaine** en amont, ~**9 Go** de disque (+9 Go de marge pour la mise à jour),
**14 Mo de RAM au repos / 22 Mo au pire**, **aucun Lidarr patché**. À faire en
`virtualisation.oci-containers` sur le modèle de `bindery.nix` (dataset sur
`/mnt/ultra/lidarr-metadata`).

**Deux comportements sont opt-in** — sans eux le conteneur gèle son premier
snapshot et ne sait rien répondre hors dataset (mapping env : `LMP_` + nom du
flag en majuscules, `-` → `_`) :

| Flag | Défaut | À poser |
|---|---|---|
| `-dataset-refresh` | **off** | `LMP_DATASET_REFRESH=72h` — vérifie `dataset-url` et bascule à chaud, sans redémarrage |
| `-fallback` | **off** | à activer pour les requêtes live MusicBrainz quand le dataset ne couvre pas |
| `-contact` | — | **obligatoire dès que `-fallback` est actif** (email ou URL, exigence MusicBrainz) |
| `-web` | off | console de comparaison `/ui`, **non authentifiée** → laisser off |

Point d'attention : la bascule se fait en écrivant le champ `metadataSource`
**par appel REST** sur l'API Lidarr → c'est de l'**état impératif**, hors-nix
(réglage en base via `IConfigService`, pas dans `config.xml` : aucun override
d'environnement n'existe). Le rendre idempotent : unité `oneshot`
`RemainAfterExit` qui tente une fois (GET → compare → PUT → vérifie, clé API
lue dans `config.xml`) et **échoue vite** si Lidarr/provider ne sont pas prêts ;
un `timer` (`OnBootSec=2min`, `OnUnitInactiveSec=5min`) la relance jusqu'au
succès — pas d'attente bloquante dans le script (une bascule réussie reste
active, ce qui désarme le timer).

Porte de sortie : ajout d'artiste et recherche de release group fonctionnels
avec le réseau vers `api.lidarr.audio` coupé.

### M3 — slskd (Soulseek) dans le netns

`slskd` 0.26.0 (AGPL-3.0-or-later) est packagé **et** a un module NixOS
(`services/web-apps/slskd.nix`). Nouveau `modules/features/downloads/slskd.nix` :

```nix
services.slskd = {
  enable = true;
  domain = null;                    # OBLIGATOIRE : l'option n'a pas de défaut,
                                    # et non-null tire nginx (on a Traefik)
  # Doit porter LES DEUX jeux : SLSKD_SLSK_USERNAME/PASSWORD (réseau Soulseek)
  # ET SLSKD_USERNAME/PASSWORD (WebUI).
  environmentFile = config.age.secrets."slskd.env".path;
  openFirewall = false;             # inutile : le netns n'a pas de firewall input
  group = "media";                  # cf. _media-service : beets doit lire derrière
  settings = {
    web.port = 5030;
    # Port forward AirVPN #2 — public = local, comme pour qBittorrent
    # (sinon les pairs annoncés tombent sur un port fermé).
    soulseek.listen_port = 54500;      # port forward AirVPN #2 (§0.2)
    directories.downloads = "/mnt/storage/medias/downloads/slskd";
    directories.incomplete = "/mnt/storage/medias/downloads/slskd-incomplete";
    shares.directories = [ "/mnt/storage/medias/musique" ];
  };
};

# Gardes mkIf comme qbittorrent.nix:36 / prowlarr.nix:38 : pas d'unité fantôme
# ni de route morte si le VPN est désactivé.
vpn.airvpn.netns.services = lib.mkIf config.vpn.airvpn.enable [ "slskd" ];
traefik.services.slskd = lib.mkIf config.vpn.airvpn.enable {
  port = 5030;
  host = config.vpn.airvpn.netns.namespaceAddress;   # comme qBittorrent
  enableAuthelia = true; category = "Médias"; icon = "di:soulseek";
};
notify.services = [ "slskd" ];
backups.sources.slskd = { paths = [ "/var/lib/slskd" ]; };  # chemin figé

# ReadWritePaths NE CRÉE PAS les répertoires, et slskd tourne slskd:media.
systemd.tmpfiles.rules = [
  "d /mnt/storage/medias/downloads/slskd 2775 slskd media - -"
  "d /mnt/storage/medias/downloads/slskd-incomplete 2775 slskd media - -"
];
systemd.services.slskd.serviceConfig.UMask = lib.mkForce "0002";
```

Spécificités du module relevées à la lecture :

- `domain` **n'a pas de défaut** → l'éval échoue si on ne le pose pas.
- Beaucoup d'options `settings` n'ont pas de défaut non plus (`rooms`,
  `shares.filters`, `transfers.*`, `retention.*`) : c'est volontaire, le module
  filtre les valeurs qui lèvent (`builtins.tryEval`) avant de générer le YAML.
  **Rien à déclarer** pour celles-là, les défauts de slskd s'appliquent.
- `StateDirectory = "slskd"` et `--app-dir /var/lib/slskd` sont **figés** : pas
  de `dataDir` configurable, donc l'état ne peut pas aller sur `/mnt/ultra`.
- `ReadOnlyPaths` est dérivé de `shares.directories`, `ReadWritePaths` des deux
  répertoires de transfert : cohérent avec le partage en lecture seule.
- Durcissement lourd (`PrivateUsers`, `ProtectSystem=strict`,
  `RestrictNamespaces`) : **validé au premier démarrage** (2026-09-30) en
  combinaison avec le `NetworkNamespacePath` posé par `vpn.nix` — systemd
  applique le netns avant l'espace d'utilisateurs, le combo fonctionne. Rien
  n'a été relâché.
- `remote_configuration` est forcé à `false` (config en store, immuable).

Port entrant : le namespace **n'a aucun firewall en entrée** (`vpn.nix` ne pose
qu'un `drop` en *output* sur la veth, policy accept) → il suffit d'un **second
port forward AirVPN**. Mais `vpn.airvpn.forwardedPort` est un **scalaire**
(`modules/hosts/hyper/configuration.nix:93`, consommé par
`qbittorrent.nix:216`) : il faut soit généraliser l'option en liste, soit
ajouter un `forwardedPortSlskd`. À noter que la sonde
`VpnMonitorMissing`/`vpn.nix:335` ne teste **qu'un** port (`grep wg0:<port>`) :
tant qu'elle n'est pas étendue, slskd n'est pas couvert par l'alerte
« forwarded port injoignable ».

Partage : uploader compte réellement sur Soulseek (traitement des files
d'attente). Partager `musique/` est le prix d'entrée, et suffit — le statut
« privileged » payant (don) n'est **jamais** nécessaire.

Porte de sortie : recherche `Beethoven Symphony 5 Kleiber` qui remonte des
résultats, un téléchargement complet, et `ip netns exec vpn curl ifconfig.co`
qui montre toujours l'IP AirVPN.

### M4 — Pipeline classique : découpage + beets

**Découpage `image+.cue`.** `unflac` **1.4** est dans nixpkgs (comme `shntool`
3.0.10 et `cuetools` 1.4.1) et c'est le meilleur des trois : il gère l'encodage
du `.cue` et tague la sortie. Deux règles :

- **Ne pas découper en place.** Le doublement d'espace se lit à deux échelles :
  **transitoire pour toute source** (le découpage écrit les pistes à côté du
  FLAC monolithique, et `copy: yes` est le défaut de beets), **permanent
  seulement pendant un seed** torrent — où l'original *doit* rester en place, et
  où l'import ne peut donc pas être un hardlink. Soulseek ne seede pas : les
  originaux peuvent partir après import (`beet import -m`).
- **Pas de script post-download qBittorrent** : il s'exécuterait *dans* le netns
  VPN. Le découpage appartient au pipeline beets, côté hôte.

**beets** 2.13.1 — **bibliothèque classique dédiée**, et rien d'autre. C'est la
conséquence de R1/R2 : Lidarr est seul à importer `populaire/`, donc la config
beets n'a ni `default:` mainstream, ni `comp:`, ni `singleton:`, ni sélecteur de
genre à faire fonctionner. Un `BEETSDIR` propre (`/mnt/ultra/beets-classique`),
une `directory:` qui est la racine classique, et le problème du sélecteur
disparaît.

Plugins **stock** (tous activés et leurs dépendances câblées dans le wrapper
nixpkgs, rien à override) :

| Plugin | Rôle |
|---|---|
| `parentwork` | **le plugin classique** : remonte la hiérarchie d'œuvres MusicBrainz jusqu'à l'œuvre-mère → `parentwork`, `parent_composer`, `work_date`, `mb_parentworkid`. Résout le problème mouvement → symphonie. **`auto` et `force` valent `no` par défaut** |
| `mbsync` | resynchronise les tags quand MusicBrainz est corrigé |
| `fetchart`, `scrub`, `replaygain` | pochettes, nettoyage des tags parasites, normalisation |
| `edit` | correction manuelle en masse — **indispensable** : c'est la seule voie pour les pressages hors MusicBrainz (§2.4), où `parentwork` ne peut rien remplir faute de `mb_workid` |

Config en store, **lue via `--config`** — et surtout pas via un `BEETSDIR`
pointé sur le store : beets écrit `library.db` et son état dans `BEETSDIR`, qui
doit donc rester un répertoire inscriptible.

```yaml
directory: /mnt/storage/medias/musique/classique
library: /mnt/ultra/beets-classique/library.db

import:
  copy: yes            # défaut ; utiliser `beet import -m` (move) sur les
                       # téléchargements Soulseek, qui n'ont pas à être conservés
  write: yes
per_disc_numbering: yes  # coffrets : la numérotation repart à 1 par disque

plugins: parentwork mbsync fetchart scrub replaygain edit

parentwork:
  auto: yes            # SANS ÇA les champs sont vides à l'écriture des tags
                       # comme au calcul du chemin (défaut : no)
  force: no

paths:
  # L'album reste l'unité sur disque (cf. R2). La hiérarchie œuvre/mouvement
  # vit dans les TAGS — c'est ce que Navidrome lit, et aucun client ne navigue
  # une arborescence d'œuvres.
  default: $albumartist/$album%aunique{} ($year)/$track $title
  singleton: Divers/$artist - $title
```

**Pourquoi pas `Compositeur/Œuvre/Interprète/`** — la tentation est forte, mais
les formats de chemin sont évalués **par item** : un récital de quatre œuvres ou
un coffret d'intégrale verrait ses pistes réparties dans quatre répertoires, et
l'album n'existerait plus comme unité. Si tu veux quand même l'arbre sur une
bibliothèque **mono-œuvre par parution**, le template robuste est :

```yaml
  default: "%if{$parent_composer,$parent_composer,$albumartist}/%if{$parentwork,$parentwork,$album}/$albumartist ($year)/$track $title"
```

Les `%if{}` sont obligatoires, pas décoratifs : sur un pressage hors
MusicBrainz les deux champs sont vides et le chemin dégénère en `//`.

Module `modules/features/medias/beets.nix` : la config en store, un wrapper
`beet-classique` qui la passe en `--config`, le répertoire d'état, et la
sauvegarde de `library.db` (seule chose non régénérable du pipeline) :

```nix
environment.systemPackages = [
  (pkgs.writeShellScriptBin "beet-classique" ''
    exec ${pkgs.beets}/bin/beet --config ${beetsConfig} "$@"
  '')
];

systemd.tmpfiles.rules = [
  "d /mnt/ultra/beets-classique 2775 logikdev media - -"
];

backups.sources.beets = {
  paths = [ "/mnt/ultra/beets-classique" ];
  # OBLIGATOIRE : le défaut est true et génère `systemctl stop beets.service`,
  # unité qui n'existe pas → le job restic échoue (storage/restic.nix:85-88).
  manageService = false;
};
```

Deux modes d'import (via le wrapper, donc `beet-classique …`) :

- `beet-classique import <dir>` — cas nominal, MusicBrainz trouve la parution.
- `beet-classique import --noautotag <dir>` puis `… edit` — **pressages absents de
  MusicBrainz**, le cas que Lidarr ne sait pas traiter du tout. Ici
  `parentwork` est inopérant (pas de `mb_workid`) : les champs `composer` /
  `work` se posent à la main.

Porte de sortie : un coffret `image+.cue` découpé, importé, avec
`parentwork`/`parent_composer` **écrits dans les tags** (vérif :
`beet-classique ls -f '$album — $parentwork — $parent_composer'`), et une sauvegarde
restic de la source `beets` qui passe.

### M5 — Navidrome + Music Assistant

`navidrome` 0.63.2, module `services/audio/navidrome.nix`. Les tags
multi-valués et les **rôles** (compositeur, chef, interprète, ingénieur) sont
arrivés en **0.55 « BFR »** (mars 2025), donc disponibles.

```nix
services.navidrome = {
  enable = true;
  settings = {
    Address = "127.0.0.1";          # Traefik devant
    Port = 4533;
    MusicFolder = "/mnt/storage/medias/musique";
  };
  # groupe primaire "media" (créé par le module seedbox) pour lire la
  # bibliothèque écrite par Lidarr/beets en UMask 0002
  group = "media";
};

traefik.services.navidrome = {
  port = 4533;
  # PAS d'Authelia : clients Subsonic natifs + provider Music Assistant, même
  # raison que Jellyfin. Navidrome a son propre système de comptes.
  category = "Médias"; icon = "di:navidrome";
};
```

Raccordement **Music Assistant** — c'est l'intérêt réel du chantier : l'écoute
passe par les Sonos (`docs/music-home.md`). État au 2026-09-30 : la VM HAOS est
**arrêtée** et la route Traefik `hass` a été retirée (`libvirt.nix:5-7`), HA
tourne en natif, et `services.music-assistant` **n'est pas encore déclaré**
(`home-assistant.nix:31`). Donc M5 inclut :

1. **Déclarer MA en natif** (`services.music-assistant`) — c'est la ligne B2 du
   lot C de `docs/home-assistant-nix-plan.md`, à traiter là-bas et pas ici :
   état, `backups.sources`, `notify.services`, route Traefik.
2. **Provider Subsonic** dans MA pointant sur `http://127.0.0.1:4533` : MA et
   Navidrome sont désormais sur la même machine → pas de saut VLAN, pas de
   dépendance au certificat public ni à Authelia.
3. **Mais MA doit rester joignable depuis `br-iot`** : les Sonos et les Cast
   tirent les URL de média/TTS *depuis* MA (le piège documenté en §3.2 d du
   dossier HA). Le loopback ne vaut que pour le sens MA → Navidrome ; **jamais
   loopback seul** pour MA elle-même.

Honnêteté sur le résultat : **aucun** serveur Subsonic ne fait de navigation
hiérarchique œuvre/mouvement. Navidrome apporte le parcours par
compositeur/chef et des mappings de tags personnalisables (`mappings.yaml`),
pas un arbre d'œuvres. Le client qui va le plus loin est Symfonium (Android,
payant). Jellyfin garde la vidéo et ne sert pas la musique.

### M6 — Soularr (optionnel)

[Soularr](https://github.com/mrusse/soularr) lit la liste « wanted » de Lidarr,
télécharge via slskd et déclenche l'import. Pas dans nixpkgs → conteneur podman
sur le modèle de `bindery.nix`. Placement : **sur l'hôte** (`--network=host`), il
atteint Lidarr en loopback et slskd à `namespaceAddress:5030` par la veth —
comme Traefik. À n'ajouter qu'après M3 validé manuellement, et **uniquement
pour le mainstream** (l'automatisation n'a pas de sens sur le classique, §2.3).

### M7 — RuTracker (optionnel, manuel)

Le meilleur tracker public en classique (section par compositeur/période,
beaucoup de lossless, pressages épuisés, scans des livrets), mais :

- **Cloudflare / DDoS-Guard + captcha**, et **FlareSolverr ne sait pas faire le
  POST de login** → il existe des proxies dédiés
  ([rutracker-cf-proxy](https://github.com/rofl3228/rutracker-cf-proxy),
  [prowlarr_rutracker_proxy](https://github.com/zxibizz/prowlarr_rutracker_proxy)).
  Prowlarr sortant par AirVPN **aggrave** la réputation IP côté Cloudflare.
- **Pas de ratio imposé** (contrairement à ce qu'on lit souvent). Les vrais
  problèmes sont les torrents anciens à 0-1 seed et la recherche en cyrillique.
- Titres hétérogènes (`Compositeur - Œuvre (Interprètes) - Année, FLAC
  (image+.cue)`) : inexploitables par un parser *arr, à traiter en M4.

Donc : recherche manuelle, grab dans la catégorie qBittorrent `classique`, puis
M4. Pas d'automatisation.

## 6. Pièges vérifiés

| # | Piège | Détail |
|---|---|---|
| P1 | Ownership Postgres | `ALTER DATABASE lidarr-{main,logs} OWNER TO lidarr` sinon pas de création de tables (PG15+) — `default.nix:21-26` |
| P2 | App-sync Prowlarr → Lidarr | Prowlarr est dans le netns : ajouter `8686` à `vpn.airvpn.netns.hostPorts` |
| P3 | Version Lidarr épinglée | nixpkgs = **3.1.0.4875**, amont = 3.1.6.5078, **support des plugins depuis 3.1.2.4938** → Tubifarry / plugin Slskd / plugins streaming **indisponibles** sans override du `package` |
| P4 | `slskd.domain` sans défaut | éval en échec si absent ; non-`null` tire nginx alors qu'on a Traefik |
| P5 | État slskd non déplaçable | `StateDirectory`/`--app-dir` figés sur `/var/lib/slskd` |
| P6 | Un seul `forwardedPort` | scalaire consommé par qBittorrent ; sonde `vpn.nix:335` étendue (WP2) : `wg0:47594` pour qBittorrent **et** `:54500` pour slskd — slskd ne se lie pas à `wg0`, un motif `wg0:<port>` pour lui ne matcherait jamais |
| P7 | Durcissement slskd × netns | **Validé** (2026-09-30) : `PrivateUsers`/`RestrictNamespaces`/`ProtectSystem=strict` fonctionnent avec `NetworkNamespacePath` — systemd applique le netns avant l'userns. Rien relâché |
| P8 | Découpage cue vs espace | Doublement **transitoire** pour toute source (découpage + `copy: yes`), **permanent** seulement pendant un seed torrent. Ne jamais découper en place |
| P9 | Script post-download | un script qBittorrent tourne **dans** le netns → faire le découpage côté hôte |
| P10 | `dataDir` sous `/mnt/ultra` | le module servarr crée `dataDir` en `0700 lidarr:lidarr` via tmpfiles ; précédent radarr/jellyfin OK. Si `tmpfiles` refuse (« unsafe transition »), basculer sur `/mnt/local/lidarr` |
| P11 | Authelia sur Navidrome | à laisser **désactivé** : le provider Subsonic de MA et les clients natifs ne savent pas faire de forward-auth |
| P12 | Métadonnées = état impératif | `metadataSource` (base `IConfigService`, pas `config.xml`) se pose par API ; bascule = oneshot fail-fast `RemainAfterExit` + timer de reprise, **pas** de boucle bloquante |
| P13 | `albumtype:classical` | **Règle morte** : `albumtype` = type primaire MusicBrainz, « classical » n'existe pas. Éliminé en faisant de beets une bibliothèque classique dédiée (R1) |
| P14 | `parentwork.auto: no` par défaut | Sans `auto: yes`, ni tags ni chemins ne sont renseignés. Et en `--noautotag`, `parentwork` reste inopérant (pas de `mb_workid`) |
| P15 | Chemins évalués **par item** | Une arborescence par œuvre éclate les récitals et coffrets multi-œuvres. L'album reste l'unité disque, la hiérarchie vit dans les tags (R2) |
| P16 | `backups.sources.beets` | `manageService = true` par défaut → `systemctl stop beets.service` inexistant → job en échec. Poser `false` (`restic.nix:85-88`, `:137-141`) |
| P17 | Répertoires slskd + creds | `ReadWritePaths` ne crée pas les dossiers (→ `tmpfiles`), et l'`environmentFile` doit porter `SLSKD_USERNAME`/`SLSKD_PASSWORD` en plus des `SLSKD_SLSK_*` |
| P18 | MA et le VLAN IoT | MA en loopback seul casse Sonos/Cast, qui tirent les URL de média/TTS depuis MA (§3.2 d du dossier HA) |
| P19 | metadata-provider : options opt-in | `-dataset-refresh` et `-fallback` sont **off** par défaut, `-fallback` exige `-contact` |

## 7. Écarté (et pourquoi)

| Écarté | Raison |
|---|---|
| **VPN-Confinement** | Doublon d'une implémentation netns maison déjà en prod |
| **Lidarr pour le classique**, même en « monitoring None » | Ne sait pas importer hors-MusicBrainz (§2.4) ni `image+.cue` |
| **Picard sur hyper** | C'est une **GUI** : rien à faire sur un serveur headless. À la rigueur depuis m4, en ponctuel |
| **Plugin Classical Extras** | Branche plugins **2.x** (fonctionne avec le Picard 2.13.3 de nixpkgs), mais jugé bogué ; Picard 3 a un registre séparé et un remplaçant « Simple Classical » en cours. `parentwork` (beets, stock) couvre le besoin, en headless |
| **Roon** (`roon-server` 2.70 est dans nixpkgs) | Le seul à modéliser vraiment œuvre/mouvement/compositeur, mais abonnement + clients propriétaires + n'alimente pas Music Assistant |
| **Plugins Lidarr / streamrip** (2.2.0 dans nixpkgs) | P3 pour les plugins ; ripper un abonnement Qobuz/Tidal viole les CGU — écarté par défaut, décision à part si besoin |
| **Apple Music Classical** pour la découverte | iOS/Android uniquement, pas de web ni de desktop → Idagio (web) si besoin depuis m4 |
| **Jellyfin comme serveur musical** | Exploite mal les tags classiques et n'est pas un provider MA naturel pour la musique |
| **Arborescence `Compositeur/Œuvre/…` sur disque** | Chemins évalués par item → éclatement des récitals et coffrets (P15), pour un gain nul : aucun client ne navigue un arbre d'œuvres, et Navidrome lit les tags |
| **beets pour le mainstream** | Doublon de Lidarr, qui importe déjà `populaire/`. beets reste cantonné au classique, ce qui supprime tout sélecteur de chemin (R1) |

## 8. Coûts

Tout le pipeline retenu est **libre et déjà packagé** : slskd (AGPL-3.0+),
Lidarr (GPL-3.0), Navidrome (GPL-3.0), beets (MIT), unflac, metadata-provider.
Compte Soulseek gratuit, **pas de ratio imposé**, don « privileged » optionnel.
Ne coûtent de l'argent que des options écartées ou périphériques : Roon,
Symfonium, les abonnements de découverte (Idagio, Apple Music Classical) et les
achats de téléchargements (Presto, eClassical, Qobuz, labels).

## 9. Ordre d'exécution

1. **M1 + M2 ensemble** — Lidarr sans provider auto-hébergé est frustrant.
2. **M3** — slskd : le vrai gain, classique *et* trous du mainstream.
3. **M4** — beets + unflac : sans lui, rien de classique n'est exploitable.
4. **M5** — Navidrome. Le raccordement Music Assistant **dépend du lot C** du
   dossier HA (`services.music-assistant` natif, pas encore déclaré) : Navidrome
   est utilisable sans, via les clients Subsonic, mais l'écoute Sonos attend ce
   lot.
5. **M6 / M7** — seulement si l'usage le demande.

`nix flake check` avant chaque commit ; déploiement `nh os switch` vers hyper.

## 10. Journal d'application

| Date | Lot | Détail |
|---|---|---|
| 2026-09-30 | WP0 | Décisions actées (§0.2). Secret `slskd.env` créé puis **rempli** (identifiants Soulseek + WebUI généré) et rekeyé → `secrets/rekeyed/hyper/60c596f6dcb34f510d2858ba91b26496-slskd.env.age` (l'ancien hash de placeholder `7a2ff49…` purgé par le rekey) ; auto-découvert (`age.secrets."slskd.env"` évalue), 4 lignes, aucun `CHANGEME`. **Reste (manuel)** : port 54500 à demander sur AirVPN ; compte Soulseek créé au 1er login slskd (WP2). Rien déployé. |
| 2026-09-30 | WP1 | **Lidarr + provider déployés** (`df2dljm…`). M1 : `lidarr.nix` (calque radarr ; Postgres `lidarr-main`/`-logs` + ALTER ownership, `dataDir=/mnt/ultra/lidarr`, UMask 0002/groupe media), tmpfiles `musique 2775`, `8686` ouvert sur la veth. M2 : conteneur `lidarr-metadata` (`--network=host`, dataset 8,8 Go / 3,0 M artistes / 4,5 M albums sur `/mnt/ultra/lidarr-metadata`, `refresh=72h` + `fallback` avec contact), bascule `metadataSource=http://localhost:5001/`. **Design bascule retenu** : oneshot fail-fast `RemainAfterExit` + timer (`OnBootSec=2min`, `OnUnitInactiveSec=5min`) — pas de boucle bloquante (l'ancienne version attendait jusqu'à 60 min). **Testé en forçant un échec** (conteneur arrêté + revert cloud) : service en échec → timer réarmé à +5 min → reprise automatique → bascule rétablie → timer désarmé. Vérifs : TLS `lidarr.hyper.logikdev.fr` = 302 (Authelia) cert valide, PG owners `lidarr`, iptables `8686` sur `veth-vpn-host`, 0 unité en échec, dossier legacy `music` supprimé. **Reste (UI, manuel)** : root folder `musique/populaire`, clients SABnzbd + qBittorrent, app Lidarr dans Prowlarr (`http://10.200.0.1:8686`), profils — puis porte de sortie (grab SAB **et** qbt, hardlink). |
| 2026-09-30 | WP2 | **slskd déployé et validé** (`7bck4fj…`). M3 : module `downloads/slskd.nix` (group media + UMask 0002, tmpfiles `slskd:media 2775`, partage `musique/` en lecture seule, guards `mkIf`, assertion sur le port) ; option `vpn.airvpn.forwardedPortSlskd` (**54500**, public = local côté AirVPN) ; sonde `vpn-monitor` étendue (`wg0:47594` pour qbt **et** `:54500` pour slskd — slskd bind `0.0.0.0`, pas de motif `wg0:`). **P7 validé** au premier démarrage : `PrivateUsers`+netns sans accroc, rien relâché. **Connexion Soulseek effective** (« Logged in as logikdev » — compte créé au 1er login), listeners 5030 + 54500 dans le netns, forward `reachable:true`, sonde `listener_bound 1`. **Recherche réelle** via l'API slskd : « Beethoven Symphony 5 Kleiber » → **245 réponses / 2583 fichiers** (Kleiber/Wiener Philharmoniker). Traefik `slskd.hyper.logikdev.fr` 302 Authelia, TLS valide. Docs : `networking.md` (ports + supervision, remplace l'avertissement obsolète « aucune supervision »), `torrent-vpn.md` (diagramme, fichiers, forwards). **Reste** : un téléchargement manuel depuis la WebUI (dossier `downloads/slskd`) pour clore la porte de sortie. |

## 11. Sources

- [NC1107/lidarr-metadata-provider](https://github.com/NC1107/lidarr-metadata-provider) · [releases Lidarr](https://github.com/lidarr/Lidarr/releases) · [Lidarr FAQ (branches, plugins)](https://wiki.servarr.com/lidarr/faq)
- [beets — plugin parentwork](https://beets.readthedocs.io/en/stable/plugins/parentwork.html) (défauts `auto: no` / `force: no`) · [beets — formats de chemin](https://beets.readthedocs.io/en/stable/reference/pathformat.html) (`%if{}`)
- [Navidrome 0.55 « BFR »](https://linuxiac.com/navidrome-0-55-music-server-and-streamer-brings-major-overhaul/) · [Navidrome — tagging](https://www.navidrome.org/docs/usage/library/tagging/)
- [Soularr](https://github.com/mrusse/soularr) · [slskd — config.md](https://github.com/slskd/slskd/blob/master/docs/config.md)
- [Prowlarr #1915 (captcha RuTracker)](https://github.com/Prowlarr/Prowlarr/issues/1915) · [rutracker-cf-proxy](https://github.com/rofl3228/rutracker-cf-proxy) · [prowlarr_rutracker_proxy](https://github.com/zxibizz/prowlarr_rutracker_proxy)
- [Simple Classical (plugin Picard 3)](https://community.metabrainz.org/t/simple-classical-picard-3-plugin-for-tagging-classical-music/815330)
- Modules nixpkgs lus : `services/misc/servarr/lidarr.nix`, `services/web-apps/slskd.nix`, `services/audio/navidrome.nix`
- Fichiers du dépôt vérifiés en r2 : `storage/restic.nix:85-88,137-141`, `hosts/hyper/libvirt.nix:5-7`, `features/home/home-assistant.nix:31`, `downloads/qbittorrent.nix:36`, `medias/prowlarr.nix:38`
