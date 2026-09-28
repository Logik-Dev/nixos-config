# Plan — maîtrise des ressources sur hyper

> Statut : planification (aucune modification appliquée).
> Date : 2026-09-28 · **révision 3 (recadrage sur mesures 7 jours)**.
> Portée : hôte `hyper` (i7-9700K, 62 GiB, zram 15,7 G, P4000 8 Go).
> **Décision r3 : le chantier « cgroups/mémoire » des révisions 1-2 est abandonné
> comme projet.** Sur 7 jours : 0 OOM kill, pression mémoire à 1,4 % au pic.
> Le problème mesurable est l'**IO**, et le premier gain disponible est
> l'**hygiène de sauvegarde** (~9,4 G d'état régénérable sauvegardé chaque nuit
> vers deux dépôts). Cinq chantiers retenus, le reste en filet déclenché par
> alerte (annexe A).

## 0. Historique des révisions

- **r1** — audit initial + plan « slices & `MemoryMax` » en 5 phases.
- **r2** — revue technique : 7 corrections (§0.1), dont deux propositions
  inopérantes et un plafond qui aurait cassé les backups.
- **r3** — recadrage : mesure de la pression réelle sur 7 jours + audit du
  contenu des sauvegardes. Le plan change de cible.

### 0.1 Corrections apportées en r2 (conservées : elles motivent l'abandon)

| # | Point r1 | Correction |
|---|---|---|
| R1 | Étape 0 = sampler maison toutes les 60 s pour lire `memory.peak` des oneshots | **Inutile** : systemd journalise déjà `Consumed … N memory peak, N read from disk, …` à l'arrêt de chaque invocation. Tous les chiffres de §2.2.1 en sortent, disponibles immédiatement |
| R2 | `snapraid-sync` mentionné en passant, absent des slices | **Premier consommateur non-VM** : pic **12,5 G** (6,8 → 8,1 → 12,5 G en 3 jours, croît avec le tableau), 340 G lus / 352 G écrits. Dans `backup.slice MemoryMax=4G` il mourait au premier run |
| R3 | `backup.slice` `MemoryMax=4G` | **Non sûr** : 22 timers restic à `02:05` avec `RandomizedDelaySec="5h"` (`storage/restic.nix:82`) → recouvrement arbitraire, et un plafond de slice *somme* les jobs concurrents |
| R4 | Phase 3 = `IOWeight` par slice | **Sans effet sur ce matériel** : `nvme0n1` en `none`, `sd[a-e]` en `mq-deadline`. `io.weight` n'est honoré que par BFQ ou un iocost configuré ; les `ionice` déjà posés par nixpkgs (snapraid `IOSchedulingPriority=7`) sont ignorés de la même façon |
| R5 | `vm.overcommit_memory=1` présenté comme un défaut subi | C'est **le module redis de nixpkgs** (`redis.nix:466`, `services.redis.*.vmOvercommit` défaut `true`, tiré par `redis-immich`). Le revenir est une régression redis, et c'est sans objet : `memory.max` s'applique quel que soit l'overcommit |
| R6 | zram = « soupape » de 15,7 G | zram, c'est de la **RAM compressée**, pas de la capacité ; et `memory.max` **ne limite pas le swap** : un cgroup plafonné à 4 G continue à consommer de la RAM via zram jusqu'à `memory.swap.max`. Tout plafond exige `MemorySwapMax` |
| R7 | Budget « 33 G + 15,6 G + infra ≈ 48,6 G < 62 G » | Arithmétique non fondée : additionner des `MemoryMax` frères ne borne rien quand l'infra est non plafonnée et que snapraid (12,5 G) et la VM sont hors somme |

## 1. Contexte

Aucun contrôle de ressources cgroup n'existe sur hyper (vérifié : 0 occurrence de
`MemoryMax`, `MemoryHigh`, `CPUWeight`, `IOWeight`, `Slice=`, `Nice=` dans
`modules/`), et les namespaces ne servent qu'à l'isolation VPN. La question
posée était : faut-il en mettre ? La mesure répond non — mais elle désigne deux
autres chantiers, plus rentables et moins risqués.

## 2. Audit (lecture seule, 2026-09-28)

Méthode : SSH en lecture seule + 7 jours d'historique Prometheus local.
systemd 261, cgroup v2, kernel 6.18.48, 0 unité en échec.

### 2.1 cgroups — constat

| Élément | Mesure |
|---|---|
| Limites mémoire | **aucune** : `MemoryMax/High=infinity`, `MemoryMin=0` partout |
| Poids CPU/IO | **aucun** : `CPUWeight=[not set]`, `IOWeight=[not set]` partout |
| Comptabilité | déjà active : `DefaultMemoryAccounting=yes`, `DefaultIOAccounting=yes` → rien à activer pour mesurer |
| systemd-oomd | **actif mais inerte** — `oomctl` : 0 cgroup surveillé (pression *et* swap) ; défauts 60 % / 30 s, swap limit 90 % |
| `DefaultTasksMax` | 76828 ; `DefaultLimitNOFILE=524288` |
| `vm.overcommit_memory` | **1**, posé par le module redis (cf. R5) ; swap = zram seul |
| Ordonnanceurs IO | `nvme0n1` : `none` · `sda…sde` (4×8 T + 1,8 T) : `mq-deadline` → **aucun contrôleur de poids IO actif** (R4) |
| Slices existants | ceux de nixpkgs seulement (`system-immich`, `system-paperless`), sans limites |
| Swap par cgroup | `memory.swap.max = max` partout ; `vm.swappiness=60`, `vm.page-cluster=3` (défauts, non ajustés pour zram) |

### 2.2 Consommation mesurée

Mémoire (usage courant / pic depuis le boot) :

| Service | RAM | Pic | | Service | RAM | Pic |
|---|---|---|---|---|---|---|
| **machine.slice** | **16,6 G** | **17,4 G** | | immich-server | 716 M | 716 M |
| └ HA VM (`machine-qemu-1`) | **15,6 G** | 16,1 G | | grafana | 481 M | 526 M |
| └ immich-ml | 488 M | 489 M | | mealie | 421 M | 422 M |
| └ bindery | 36 M | 38 M | | postgresql | 383 M | 400 M |
| jellyfin | 1 760 M | 1 794 M | | cross-seed | 338 M | 1 424 M |
| unifi | 1 354 M | 1 358 M | | seerr / tika | 301 / 297 M | 329 / 299 M |
| n8n | 1 008 M | 1 379 M | | sonarr / radarr | 285 / 238 M | 292 / 244 M |
| | | | | sabnzbd / audiobookshelf | 171 / 159 M | 277 / 258 M |
| | | | | prowlarr / traefik | 190 / 134 M | 194 / 143 M |
| | | | | adguardhome / ollama / rankoder | 98 / 231 / 49 M | 99 / 363 / 69 M |

Pics de slices : `system.slice` 25,0 G · `machine.slice` 17,4 G · `user.slice`
1,9 G. État global : 23 G utilisés, 38 G en cache, **39 G disponibles**, zram
700 K utilisés sur 15,7 G.

**Découverte — VM HA** : `Max memory = 15,6 G`, `hard_limit=unlimited`,
2 vCPU. `dommemstat` : `rss=15,6 G` mais **`unused=15,1 G`** ⇒ l'hôte immobilise
15,6 G pour une VM qui en utilise ~0,5 G, sans balloon actif. Le domaine est
**impératif** : `hosts/hyper/libvirt.nix` n'active que `virtualisation.libvirtd`,
le XML n'est pas dans le flake.

CPU : `nix-daemon` tourne en `CPUSchedulingPolicy=0` (OTHER),
`IOSchedulingClass=2` (best-effort), `Nice=0` — soit **à égalité avec Jellyfin
et Postgres**. Un build sature les 8 cœurs. Governor `powersave`.

GPU : P4000 8 Go, 3 MiB utilisés, aucun process CUDA à l'audit. La VRAM est déjà
arbitrée au niveau applicatif (`OLLAMA_MAX_LOADED_MODELS=1`,
`OLLAMA_KEEP_ALIVE=5m` dans `ai/ollama.nix`).

#### 2.2.1 Batch — pics réels lus au journal systemd

| Unité | Pic mémoire | Lu / écrit | CPU | Remarque |
|---|---|---|---|---|
| **snapraid-sync** | **12,5 G** (26/09 : 6,8 · 27/09 : 8,1) | **340 G / 352 G** | 12 min 13 s | croît avec le tableau ; sur les HDD `mq-deadline` |
| restic-backups-adguard | 2,6 G | 4,7 G / 10 M | 27 s | **cf. §2.5 : 99 % de querylog** |
| restic-backups-pg-dump | 1,4 G | 3,4 G / 30 M | 21 s | légitime |
| restic-backups-jellyfin | 630 M | 871 M / 159 M | 40 s | |
| restic-backups-radarr | 409 M | 344 M / 118 M | 26 s | |
| restic-backups-* (médiane) | 50–110 M | < 100 M | 8 s | ~15 jobs |

### 2.3 namespaces / sandboxing — constat

Scores `systemd-analyze security` : podman-bindery / podman-immich-ml 9,8 ·
podman / libvirtd / sshd / nix-daemon 9,6 · cross-seed / sabnzbd /
audiobookshelf 9,2 · mealie / prowlarr / tika / nscd 8,2 · rankoder 6,8 ·
n8n / fail2ban / glance / traefik 5,6–5,7. Déjà bons : vaultwarden 1,2 ·
postgres 1,3 · authelia 1,4 · ollama 1,4 · adguard 1,6 · jellyfin 1,8 ·
**snapraid-sync** (durci par nixpkgs : `ProtectSystem=strict`,
`MemoryDenyWriteExecute`, caps réduites — bon gabarit à réutiliser).

Les unités maison n'ont ni `ProtectSystem/Home`, ni `PrivateDevices/Tmp`, ni
`SystemCallFilter`, ni `CapabilityBoundingSet`. Conteneurs podman rootful sans
user namespace, Bindery en `net=host`, rootfs inscriptible.

### 2.4 Pression réelle — 7 jours d'historique Prometheus

C'est la mesure qui recadre tout le dossier.

| Indicateur | Valeur sur 7 j | Lecture |
|---|---|---|
| `increase(node_vmstat_oom_kill[7d])` | **0** | aucun OOM kill, jamais |
| pression **mémoire**, pic (`rate(node_pressure_memory_waiting[10m])`) | **0,014** (1,4 %) | négligeable |
| pression **IO**, pic | **0,514** (51 %) | contention réelle, par salves |
| pression IO, moyenne horaire max | 0,062 à **10 h** (snapraid) · 0,050 à **02 h** (backups) | les deux fenêtres batch |
| `/proc/pressure/memory` depuis le boot | 78 s cumulées, `full avg300 = 0` | rien |

Profil horaire de la pression IO (pic sur 7 j, pas de 10 min) : creux à 03-06 h
et 14-17 h ; pics à 01 h (0,50), 02 h (0,45), **10 h (0,44 — snapraid)**, 12-13 h
(0,51), 07 h (0,39). Les pics de 12-13 h ne correspondent à aucune unité batch
(aucun `Consumed` au journal) : activité média/organique.

**Conclusion : il n'y a pas de problème de mémoire sur hyper. Il y a une
contention IO modérée et par salves, dont deux salves sur trois sont du batch
que l'on peut déprioriser.**

### 2.5 Contenu des sauvegardes — l'anomalie la plus rentable du dossier

Audit de ce que les 22 jobs restic embarquent réellement :

| Source | État total | Dont **régénérable / sans valeur de restauration** | Vraie config |
|---|---|---|---|
| **adguard** | **5,4 G** | **5,4 G** — `data/querylog.json` 2,4 G + `.json.1` 3,0 G (`querylog.interval: 90d`) | `AdGuardHome.yaml` 8 K + `filters` 4,2 M + `stats.db` 244 K + `sessions.db` 24 K |
| **jellyfin** | 3,0 G | `metadata/People` **2,3 G** (portraits d'acteurs) + `metadata/Studio` 23 M + `log` 20 M | `data` 417 M (BDD : utilisateurs, état de visionnage) + `metadata/library` 338 M |
| **radarr** | 1,4 G | `MediaCover` 1,3 G + `logs` 102 M | BDD ~10 M |
| **sonarr** | 196 M | `MediaCover` 94 M + `logs` 102 M | BDD, quelques Mo |
| **prowlarr** | 38 M | `logs` 33 M + `Definitions` 5,4 M (resynchronisées automatiquement depuis l'amont) | BDD, quelques centaines de Ko |
| | | **≈ 9,4 G** | |

Ce volume part **chaque nuit vers les deux dépôts** (USB + Hetzner). Effets
mesurés côté dépôts USB : `adguard` 605 M, `radarr` 3,9 G pour 1,4 G d'état,
`jellyfin` 3,8 G pour 3,0 G d'état — l'écart, c'est le brassage quotidien de
`MediaCover`/`metadata`/querylog multiplié par la rétention
(7 j + 3 sem + 6 mois + 2 ans).

Jellyfin exclut déjà `log`, `cache`, `transcodes` — mais pas `metadata`, dont
**89 % est un cache de portraits d'acteurs** (`People`). Les autres sources
n'ont aucun `exclude`.

Deux effets secondaires, tous deux indésirables :

- **Vie privée** : 90 jours de requêtes DNS de tout le foyer, répliqués
  hors-site chez Hetzner chaque nuit.
- **Quota / coût Storage Box** (point de vigilance connu) : ~8 G de dépôt
  récupérables côté Hetzner, et autant de bande passante montante par nuit.

### 2.6 Risques retenus, repriorisés par la mesure

1. **~9,4 G d'état régénérable sauvegardé deux fois par nuit** (§2.5) — dont
   5,4 G de journaux DNS envoyés hors-site. Aucun bénéfice de restauration.
2. **15,6 G immobilisés par la VM HA** dont 15,1 G inutilisés — un `virsh` d'une
   ligne, zéro cgroup.
3. **Contention IO** aux fenêtres batch (02 h backups, 10 h snapraid), **sans
   levier possible** avant de changer d'ordonnanceur sur les rotatifs (R4).
4. Un build nix (8 jobs) est à égalité de priorité CPU/IO avec Jellyfin.
5. Concurrence non bornée des 22 jobs restic (`RandomizedDelaySec="5h"`).
6. Aucun biais de l'OOM killer vers le jetable — risque non matérialisé (0 kill
   en 7 j) mais l'assurance est gratuite.
7. ~12 unités maison non sandboxées ; détritus `nscd`/`acpid`/`mandb`.

## 3. Verdict

Le plan r1/r2 investissait ~90 % de l'effort sur la mémoire, où il n'y a rien à
gagner aujourd'hui, et son unique volet visant la contention réelle (IO) était
inopérant faute d'ordonnanceur adéquat. Construire une topologie de slices sur
~40 services avec des plafonds calibrés, c'est un coût permanent
(chaque nouveau service doit choisir sa slice, chaque plafond doit être
re-mesuré quand la charge change) en échange d'une assurance contre un sinistre
qui ne s'est jamais produit — et le seul mécanisme capable, dans tout ce
dossier, de casser un service qui fonctionne.

**On garde de l'idée cgroup ce qui est purement protecteur (§4.4) et gratuit, on
abandonne les plafonds, et on redéploie l'effort sur les deux chantiers que la
mesure désigne : le contenu des sauvegardes et la priorité du batch.**

Sur les autres directions envisagées :

- **Changement de stratégie de sauvegarde** : oui, mais pas d'architecture — le
  schéma restic 2 dépôts + pgBackRest PITR est sain. C'est le *périmètre* des
  sources qui est à corriger (§4.1), et c'est le meilleur rapport effort/gain du
  dossier.
- **Alternance / arrêt-relance de services à la demande** : **rejeté**. 39 G
  disponibles, 0 OOM kill, pression mémoire à 1,4 %. On ajouterait de la
  complexité et des pannes d'ordonnancement pour récupérer une ressource
  abondante.
- **Amélioration globale de la gestion des ressources** : c'est §4.3 (priorité
  du batch) — le bon niveau d'abstraction est l'ordonnanceur et la niceness,
  pas le plafond.

## 4. Chantiers retenus

Ordre = rentabilité décroissante. C1 et C2 sont indépendants du reste.

### C1 — Hygiène de sauvegarde (≈ 9,4 G/nuit, × 2 dépôts)

| Fichier | Changement |
|---|---|
| `networking/adguard.nix` | 1. `services.adguardhome.settings.querylog.interval = "7d"` — corrige la cause (5,4 G d'état vivant sur le disque système) ; `mutableSettings = true` fusionne les valeurs nix **avec précédence** sur l'UI (vérifié dans le module nixpkgs). 2. `backups.sources.adguard.exclude = [ ".../data/querylog.json*" ]` — le journal DNS n'a aucune valeur de restauration, et ne doit pas partir hors-site |
| `medias/radarr.nix`, `medias/sonarr.nix` | `exclude = [ "<dataDir>/MediaCover" "<dataDir>/logs" ]` — jaquettes régénérées automatiquement par l'appli |
| `medias/prowlarr.nix` | `exclude = [ "<dataDir>/logs" "<dataDir>/Definitions" ]` — `Definitions` est resynchronisé automatiquement depuis l'amont |
| `medias/jellyfin.nix` | ajouter `metadata/People` (2,3 G) et `metadata/Studio` (23 M) aux `exclude`, **et garder `metadata/library`** (338 M) : `People` est un pur cache de portraits, retéléchargé à la demande, sans risque de perdre une édition manuelle — contrairement à `library`, qui porte les images et `.nfo` au niveau des items |
| tous | vérifier au passage les autres sources jamais auditées (`unifi`, `n8n`, `mealie`, `bindery`, `audiobookshelf`, `sabnzbd`, `seerr`, `rankoder`) avec la même grille : `logs`, `cache`, `*Cover`, `thumbnails` |

Effets attendus, vérifiables : job adguard **4,7 G lus → ~5 M**, son pic mémoire
**2,6 G → négligeable** ; ~8 G de dépôt récupérés de chaque côté après
`forget --prune` (déjà dans le script) ; disparition de la principale source
d'IO de la fenêtre 02-07 h.

Validation : `restic -r <repo> stats latest` avant/après, `journalctl -u
restic-backups-adguard --grep 'memory peak'`, `du -sh` de l'état AdGuard à J+8,
et **un test de restauration** de chaque source modifiée (les drills existants
couvrent déjà ce chemin).

> Ce chantier rend caduc, à lui seul, tout le dimensionnement mémoire de
> `backup.slice` de la r1.

#### Référence « avant » — dépôts restic USB au 2026-09-28

Relevée avant déploiement, pour mesurer l'effet des excludes après la première nuit.

| Dépôt | Taille | Attendu après |
|---|---|---|
| `radarr` | **3,9 G** | forte baisse (1,3 G de `MediaCover` + 101 M de `logs` retirés de la source) |
| `jellyfin` | **3,8 G** | forte baisse (2,3 G de `metadata/People` retirés) |
| `adguard` | **605 M** | quasi nul (5,4 G de querylog retirés) |
| `sonarr` | 126 M | baisse (94 M `MediaCover` + 102 M `logs`) |
| `prowlarr` | 5,2 M | stable en taille, mais plus de brassage quotidien |
| `pg-dump` / `immich` | 1,1 G / 553 G | inchangés (hors périmètre C1) |

Les baisses n'apparaissent qu'après le `forget --prune` qui suit, pas à la
première sauvegarde.

#### Corrections de mesure relevées à l'implémentation

- **`prowlarr` : 9,7 M, pas 38 M.** Les données vivantes sont dans
  `/var/lib/private/prowlarr` (le chemin effectivement sauvegardé) ; les 38 M
  mesurés dans `/mnt/ultra/prowlarr` sont un **résidu orphelin** d'une ancienne
  configuration (cf. le commentaire de `prowlarr.nix:30-33`). À supprimer.
- Total régénérable retiré de la sauvegarde : **≈ 9,3 G** (et non 9,4 G).
- **Dépôts restic orphelins** : `uptime-kuma`, `jackett`, `torrent` et `data`
  (973 M) existent sur `/mnt/usb/restic` mais ne correspondent à aucune entrée de
  `backups.sources` — ~1 G de données mortes sur l'USB, et vraisemblablement
  autant sur le Storage Box. Nettoyage à faire, même esprit que C1.

### C2 — VM Home Assistant : 15,6 G → 4 G

Gain : ~11 G rendus, aucun cgroup, réversible.

- `virsh setmaxmem home-assistant 4G --config` puis `setmem`, après vérification
  de `<memballoon model='virtio'/>` dans le XML. `maxmem` exige un **arrêt de la
  VM** → courte indisponibilité HA à planifier.
- **Ne pas** poser `MemoryMax` sur `machine.slice` : qemu serait tué, l'invité
  n'a aucun moyen de rendre des pages (cf. §5 pièges).
- Marge : l'invité consomme ~0,5 G mesuré ; 4 G = 8× la charge observée.
- **Gap déclaratif** : le domaine est impératif. Livrable associé —
  consigner le XML + la procédure dans `docs/`, ou trancher l'adoption d'un
  domaine déclaratif. À décider, pas à improviser.

Validation : `virsh dommemstat home-assistant` (`unused` doit rester > 2 G en
régime), HA fonctionnel, add-ons démarrés, `free -g` sur l'hôte.

### C3 — Priorité du batch (le seul volet qui vise la contention mesurée)

| Fichier | Changement | Pourquoi |
|---|---|---|
| `system/io-scheduler.nix` **(nouveau)** | règle udev : `ACTION=="add\|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"` — NVMe laissé en `none` | **Prérequis** : sans BFQ, `IOWeight` *et* les `ionice` déjà posés par nixpkgs sont des no-op (R4). C'est ce qui rend effectif le `IOSchedulingPriority=7` que snapraid porte déjà |
| `system/nix.nix` | `nix.daemonCPUSchedPolicy = "idle"` + `nix.daemonIOSchedClass = "idle"` (côté NixOS) | Un build cesse de concurrencer Jellyfin/Postgres. Options NixOS de première classe (`nix-daemon.nix:95,129`), effet immédiat — `SCHED_IDLE` ne dépend pas de l'ordonnanceur bloc |
| `storage/restic.nix` | `IOSchedulingClass = "idle"`, `CPUSchedulingPolicy = "batch"`, `Nice = 19` sur les jobs | Les jobs cèdent le passage au streaming ; devient réel avec BFQ sur les cibles rotatives |

Constats d'implémentation (2026-09-28) :

- **BFQ est un module non chargé** (`CONFIG_IOSCHED_BFQ=m`, absent de la liste
  `none [mq-deadline] kyber`) → la règle udev seule ne suffit pas, d'où
  `boot.kernelModules = [ "bfq" ]`. `CONFIG_BFQ_GROUP_IOSCHED=y` en revanche est
  bien présent, donc un `IOWeight` par slice deviendrait réel (plan annexe A).
- **`snapraid-sync` est corrigé gratuitement** : nixpkgs lui posait déjà
  `Nice=19`, `CPUSchedulingPolicy=batch` et `IOSchedulingPriority=7`, qui
  n'avaient jamais rien fait sous `mq-deadline`. Aucun code à écrire : BFQ les
  rend effectifs. C'est le plus gros consommateur d'IO du dossier (340 G lus).
- **Asymétrie CPU/IO assumée sur `nix-daemon`** : CPU en `idle` (SCHED_IDLE ne
  bride rien sur une machine au repos), mais IO en `best-effort` prio 7 et **pas**
  en classe `idle` — nixpkgs prévient que l'IO `idle` « might slow down or starve
  crucial configuration updates during load », et un déploiement ici est
  interactif. Le coût de cette prudence est nul : `/nix` est sur le NVMe, dont
  l'ordonnanceur reste `none`, où ionice n'a aucun effet.
- **Le réglage passe par un drop-in**, pas par l'unit : `nix-daemon.service` est
  un lien vers l'unit du paquet nix (`systemd.packages`), et NixOS écrit les
  surcharges dans `nix-daemon.service.d/overrides.conf`. Vérifier là, pas dans
  l'unit.
- **Le module neuf doit être suivi par git avant le switch** : les flakes
  ignorent les fichiers non suivis, et `nixos-rebuild --flake '.#hyper'` échoue
  sur `undefined variable 'io-scheduler'`. Contourner en validation avec
  `--flake 'path:.#hyper'` ; pour déployer, commiter (jj) d'abord.

Optionnel, si la pression IO reste visible après coup : `IOReadBandwidthMax` /
`IOWriteBandwidthMax` (`io.max`) sur les jobs lourds — fonctionne **quel que
soit** l'ordonnanceur, y compris sur le NVMe resté en `none`.

Validation : `cat /sys/block/sda/queue/scheduler`, `ionice -p <pid>` pendant un
sync, et surtout **comparaison avant/après du pic de
`rate(node_pressure_io_waiting_seconds_total[10m])` aux fenêtres 02 h et 10 h**
(référence : 0,45 et 0,44).

### C4 — Sérialiser la fenêtre nocturne

`storage/restic.nix:82` : `RandomizedDelaySec = "5h"` sur 22 timers pointés à
`02:05`. Remplacer par un échelonnement déterministe (`OnCalendar` décalés) ou un
chaînage derrière un `backup.target`.

Pourquoi c'est mieux qu'un plafond mémoire : ça borne la concurrence **à la
source**, donc le budget mémoire devient déterministe sans que rien ne puisse
être tué, et l'IO simultané diminue. Avec C1 (qui retire le plus gros job), la
fenêtre devrait se réduire nettement.

Validation : deux nuits observées au journal — aucun recouvrement, fenêtre
totale plus courte, pas de job manqué (`Persistent = true` conservé).

### C5 — Filet OOM et fil-piège (aucun plafond)

Volet cgroup **conservé** de la r1/r2, parce qu'il est purement protecteur : il
ne peut pas dégrader un service qui fonctionne.

`system/resource-control.nix` **(nouveau)**, importé par hyper seul :

- Noyau critique (adguardhome, traefik, authelia-main, vaultwarden, postgresql,
  sshd, tailscaled) : `MemoryMin`, `ManagedOOMPreference = "avoid"`,
  `OOMScoreAdjust` négatif.
- Batch (snapraid-sync/scrub, restic-*, rankoder, immich-ml, ollama,
  nix-daemon) : `OOMScoreAdjust` positif.
- `ManagedOOMPreference` **et** `OOMScoreAdjust` sont complémentaires, pas
  redondants : oomd **ignore** `OOMScoreAdjust`, le killer noyau ignore
  `ManagedOOMPreference`.
- Pas de `MemoryMax`, pas de `MemoryHigh`, pas de slice nouvelle. Membres
  déclarés ici et non par module : sans plafond, il n'y a pas de topologie à
  maintenir, donc le pattern FAC-5 ne s'impose pas.

`monitoring/prometheus-alerts.nix` — fil-piège sur **métriques déjà exposées**
(aucun exporteur à écrire, vérifié sur `localhost:9100`) :

| Alerte | Expression | Seuil |
|---|---|---|
| `HostOOMKill` | `increase(node_vmstat_oom_kill[15m]) > 0` | critique, immédiat (référence : 0 sur 7 j) |
| `HostMemoryPressure` | `rate(node_pressure_memory_waiting_seconds_total[10m]) > 0.1` | warning, `for: 15m` (7× le pic observé) |
| `HostIOPressureSustained` | `rate(node_pressure_io_waiting_seconds_total[10m]) > 0.4` | warning, `for: 30m` — le pic actuel (0,51) est bref, un palier de 30 min est anormal |
| `HostMemoryAvailableLow` | `node_memory_MemAvailable_bytes < 8e9` | warning, `for: 10m` (référence : 41 G) |

**C'est ce fil-piège qui remplace les Phases 2-3 de la r1.** Si une alerte sonne,
la spécification slices + plafonds est prête en annexe A — on l'applique alors
sur la base d'un incident réel et de chiffres à jour, pas d'un pronostic.

### Hors chantiers — traité au fil de l'eau

- **Sandboxing des ~12 unités maison** : pas un projet. À faire quand on touche
  l'unité pour une autre raison, en réutilisant le gabarit `snapraid-sync` de
  nixpkgs. Un score `systemd-analyze` n'est pas un objectif en soi.
- **Ménage `nscd`/`acpid`/`mandb`** : à glisser dans un passage de maintenance.
- **zram** : corriger le commentaire de `security/hardening.nix:11-21` — ce
  n'est pas une soupape de capacité mais de la RAM compressée, et ça ne protège
  pas d'une fuite (R6). Documentation seulement, pas de changement de config.

## 5. Abandonné, et pourquoi

| Abandonné | Raison |
|---|---|
| Topologie de slices sur ~40 services + `MemoryMax`/`MemoryHigh` par slice | 0 OOM kill et 1,4 % de pression mémoire sur 7 j. Coût permanent (calibrage, choix de slice à chaque nouveau service), et seul mécanisme du dossier capable de casser un service sain. Spec conservée en annexe A, déclenchée par alerte |
| `backup.slice MemoryMax=4G` | Aurait cassé les backups (R3) — et C1 supprime le besoin |
| `maintenance.slice` avec plafond pour snapraid | Empreinte croissante avec le tableau (6,8 → 12,5 G) : tout plafond serait obsolète au prochain ajout de disque. C3 (ionice/BFQ) traite le vrai problème, qui est l'IO |
| Sampler cgroup toutes les 60 s + textfile collector | Redondant avec le journal systemd (R1) |
| Device cgroup GPU (`DeviceAllow`) | La ressource rare est la VRAM (8 Go), que les cgroups ne contrôlent pas ; l'arbitrage est déjà dans `ai/ollama.nix` |
| Revenir `vm.overcommit_memory` à 0/2 | Option du module redis (R5), sans effet sur l'objectif |
| `PrivateUsers` sur les oneshots root | Casse l'accès aux fichiers d'autres UID et l'auth `peer` de Postgres. Gain nul ici |
| Podman rootless + userns | Chantier lourd (migration du stockage, GPU passthrough immich-ml), aucun incident à l'appui |
| **Alternance / arrêt à la demande de services** | 39 G disponibles. On ajouterait des pannes d'ordonnancement pour récupérer une ressource abondante |
| Inchangé depuis r1 | CPU pinning fin, time namespace, PID namespace maison, un netns par service, réintroduire `fwMark`/kill-switch |

## 6. Séquencement et validation

| Étape | Contenu | Porte de sortie |
|---|---|---|
| 1 | **C5** (fil-piège d'alertes seul) — **fait, construit, non déployé** (2026-09-28) | 3 alertes ajoutées (`HostOOMKill`, `MemoryStallSustained`, `IoStallSustained`), validées par `promtool` au build. La 4ᵉ (`HostMemoryAvailableLow`) a été **abandonnée** : `HighMemoryPressure` couvrait déjà le seuil `MemAvailable` |
| 2 | **C1** (hygiène de sauvegarde) — **fait, construit, non déployé** (2026-09-28) | Excludes en place sur adguard/jellyfin/radarr/sonarr/prowlarr + `querylog.interval = "7d"`. Reste à vérifier après une nuit : `restic stats` en baisse, pic mémoire adguard effondré, **restauration testée** pour chaque source modifiée |
| 3 | **C2** (VM HA) | `dommemstat unused > 2 G`, HA + add-ons OK, ~11 G rendus sur l'hôte |
| 4a | **C3** (priorité batch) — **fait, construit, non déployé** (2026-09-28) | `io-scheduler.nix` (BFQ sur les 5 rotatifs + `boot.kernelModules`), `nix-daemon` en `CPUSchedulingPolicy=idle` / `IOSchedulingClass=best-effort` prio 7, jobs restic en `Nice=19` + `batch` + `IOSchedulingClass=idle`. Vérifié dans le système construit. Porte de sortie : pic de pression IO à 02 h et 10 h en baisse vs référence (0,45 / 0,44) |
| 4b | **C4** (sérialisation de la fenêtre) | aucune fenêtre batch allongée au point de déborder |
| 5 | **C5** volet protecteur (`MemoryMin`, `ManagedOOMPreference`, `OOMScoreAdjust`) | `systemctl show <unit> -p MemoryMin -p ManagedOOMPreference` conforme |

À chaque étape : `nix flake check` (+ `--all-systems --no-build`),
`nixos-rebuild test`, `systemctl --failed` vide, DNS/ingress/postgres/VPN OK,
puis `switch`. Rappel déploiement : `ssh hyper 'nh os switch'` — et si
l'activation échoue, `nixos-rebuild boot` + reboot (nh ne persiste pas la
génération en cas d'erreur d'activation).

### Pièges (valables pour les chantiers retenus)

- **`MemoryMax` sur `machine.slice` ne fait pas maigrir une VM** : qemu est tué,
  l'invité n'a aucun moyen de rendre des pages. Le levier est la taille du
  domaine + le balloon virtio.
- `IOWeight` / `ionice` sont des **no-op** sans BFQ (ou iocost) — d'où l'ordre
  de C3.
- oomd **ignore** `OOMScoreAdjust` ; le killer noyau ignore
  `ManagedOOMPreference`. Poser les deux.
- `systemd.oomd.enableSystemSlice` / `enableRootSlice` sont des
  `mkEnableOption`, donc **déjà `false`** : rien à poser, juste à ne jamais les
  activer (oomd y tuerait dans `system.slice`, donc l'infra).
- Les excludes restic ne rétrécissent pas l'historique : c'est
  `forget --prune` (déjà dans le script) qui libère, au run suivant.
- Un `exclude` mal ciblé est silencieux jusqu'à la restauration → le test de
  restauration de C1 n'est pas optionnel.
- Les unités du netns VPN acceptent `Slice=` et les réglages OOM (cgroup ≠
  namespace).

## 7. Documentation

`docs/audit-2026-09.md` : nouveaux IDs `RES-*` (C1 à C5) + journal. Corriger le
commentaire zram de `security/hardening.nix:11-21`. Consigner la procédure VM HA
(C2). Ce document reste la référence de décision.

---

## Annexe A — Spécification slices + plafonds (plan de secours, non appliqué)

Conservée telle qu'issue de la r2, **à n'appliquer que si une alerte de C5
sonne**, et après avoir re-mesuré. Elle n'est pas un backlog : c'est une réponse
à incident déjà rédigée.

Principes (corrigés r2) : `MemoryHigh` d'abord (freine et alimente PSI),
`MemoryMax` seulement sur emballement observé et à `pic × 2` ; **tout plafond
vient avec `MemorySwapMax`** (sinon la RAM fuit par zram, R6) ; pas de budget
additif (R7) ; `TasksMax` par slice comme garde-fou runaway.

| Slice | Membres | Rôle |
|---|---|---|
| `infra.slice` | adguardhome, traefik, authelia-main, vaultwarden, postgresql, tailscaled, sshd, fail2ban, mosquitto, zigbee2mqtt, alertmanager, unifi | protégée : `MemoryMin`, jamais de plafond |
| `ai.slice` | ollama, conteneur `immich-ml` | batch GPU |
| `media.slice` | jellyfin, sonarr, radarr, prowlarr, seerr, sabnzbd, qbittorrent, cross-seed, freeleech-farmer, audiobookshelf, rankoder, `bindery` | interactif + batch |
| `home.slice` | n8n, mealie, syncthing | |
| `backup.slice` | restic-backups-*, pgbackrest, pg-dumpall, drills | concurrence à borner par C4 d'abord |
| `maintenance.slice` | snapraid-sync/scrub, btrfs-scrub, scopes ad hoc | **jamais de `MemoryMax`** (empreinte croissante) |
| `system-immich` / `system-paperless` | (nixpkgs) | `systemd.slices.system-immich` existe en amont (`immich.nix:406`) → notre `sliceConfig` fusionne, pas de conflit |

Appartenance déclarée par le module propriétaire (pattern FAC-5, comme
`vpn.airvpn.netns.services`). Conteneurs podman rootful : `--cgroup-parent=<slice>`
dans `extraOptions` (à valider) ou `--memory=`/`--cpus=` par conteneur.

Pièges spécifiques : `sliceConfig` pour les slices, `Slice=` dans
`serviceConfig` ; ne pas plafonner `system.slice` (parent de
`system-immich`/`system-paperless`) ; `OOMPolicy` vaut **déjà `stop`** par défaut
pour les services — le vrai piège est les unités nixpkgs en `Restart=always`,
qui boucleront au lieu d'alerter ; restic tolère mal un `MemoryMax` serré
(cache multi-Go).

## Annexe B — Commandes d'audit

```bash
# Pics par invocation (oneshots inclus) — la source à privilégier
journalctl -u 'restic-backups-*' --since '3 days ago' | grep 'memory peak'
journalctl -u snapraid-sync --since '7 days ago' | grep Consumed

# Pression réelle (la mesure qui décide)
curl -sG --data-urlencode \
  'query=increase(node_vmstat_oom_kill[7d])' localhost:9090/api/v1/query
curl -sG --data-urlencode \
  'query=max_over_time(rate(node_pressure_io_waiting_seconds_total[10m])[7d:10m])' \
  localhost:9090/api/v1/query
cat /proc/pressure/memory /proc/pressure/io

# Contenu des sauvegardes
sudo du -sh /var/lib/private/AdGuardHome/data/* | sort -h
sudo du -sh /mnt/ultra/{jellyfin,radarr,sonarr,prowlarr}/* | sort -h
sudo du -sh /mnt/ultra/jellyfin/metadata/* | sort -h
sudo du -sh /mnt/usb/restic/* | sort -h
restic -r /mnt/usb/restic/<source> stats latest

# État cgroup / oomd
systemd-analyze security --no-pager
systemctl show --no-pager -p MemoryCurrent -p MemoryPeak '*.service'
systemctl show --no-pager -p MemoryMin -p ManagedOOMPreference \
  -p OOMScoreAdjust -p IOSchedulingClass <unit>
systemd-cgtop -m ; oomctl

# IO : vérifier qu'un levier existe avant de le poser
cat /sys/block/{nvme0n1,sda}/queue/scheduler

# VM HA
virsh -c qemu:///system dommemstat home-assistant
virsh -c qemu:///system dumpxml home-assistant | grep -A2 memballoon
```

## Références internes

- `modules/features/networking/adguard.nix:62-72` (source adguard, C1)
- `modules/features/storage/restic.nix:79-83` (timers, C4)
- `modules/features/system/nix.nix` (nix-daemon, C3)
- `modules/hosts/hyper/libvirt.nix` (domaine HA impératif — gap déclaratif, C2)
- `modules/hosts/hyper/snapraid.nix` (plus gros consommateur batch)
- `modules/features/security/hardening.nix:11-21` (zram, commentaire à corriger)
- `modules/features/downloads/vpn.nix` (pattern netns / FAC-5)
- `docs/audit-2026-09.md` (IDs SEC/MON/BAK/FAC)
- `docs/vpn-netns-plan.md` (gabarit de doc de plan)
