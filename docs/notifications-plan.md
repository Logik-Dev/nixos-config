# Plan — refonte des notifications sur hyper

> Statut : **N1 et N2 déployés** (hyper, génération 504, 2026-09-29 06:57) et
> vérifiés en production. **N3 implémenté et testé, non déployé.** N4 en
> planification, et déconseillé en l'état (cf. §4.1).
> Date : 2026-09-28 · **révision 2 (recadrage sur preuves)**.
> Portée : chaîne d'alerte de `hyper` — `notify-failure@`, `push_ntfy`,
> Alertmanager + `alertmanager-ntfy`, ntfy 2.27.0, 3 topics.
> **Décision r2 : le chantier n'est pas d'abord cosmétique.** La mesure a mis au
> jour une **perte silencieuse d'alertes** (une panne réelle non notifiée le
> 2026-09-28, sans aucune trace) et **15 unités critiques hors du radar
> Prometheus**. La lisibilité, qui motivait le plan r1, passe en second.

## 0. Historique des révisions

- **r1** — diagnostic initial : titre constant, dump de journal brut,
  duplication Alertmanager, proposition d'un formateur déterministe (P1) et
  d'un résumeur LLM local (P2).
- **r2** — vérification de chaque affirmation sur l'hôte (cache ntfy, journal
  complet sur 27 jours, binaires, sondes systemd, bancs LLM). 6 corrections,
  2 constats nouveaux, priorités inversées.

### 0.1 Corrections apportées en r2

| # | Point r1 | Correction (preuve) |
|---|---|---|
| R1 | Le problème est la lisibilité | **Il y a d'abord une perte d'alertes.** `cf-ddns` échoue à 14:03:07 le 2026-09-28, `notify-failure@` tourne, **aucun message n'arrive** : `ntfy-sh` n'écoute qu'à 14:03:08. `push_ntfy` fait `curl -s … >/dev/null 2>&1 \|\| true` → zéro trace. Voir §2.1 |
| R2 | Supprimer `SystemdUnitFailed` pour les unités déjà dans `notify.services` | **Régression.** Le `unit-include` de node_exporter ne matche que 58 des 73 unités de `notify.services` : **15 sont invisibles** à `SystemdUnitFailed`, dont `qbittorrent`, `vpn-monitor`, `unifi`, `tailscaled`, `pg-dumpall`, `pgbackrest-*`. Pour elles `notify-failure` est le **seul** canal — et c'est celui qui perd des messages. `SystemdUnitFailed` est aussi le seul à émettre un `Resolved`. Voir §2.4 |
| R3 | `homelab-alerts` est propre, c'est le modèle à généraliser | **Non.** Tags réellement reçus : `red_circle,alertname = PgWalArchiveFailures,instance = 127.0.0.1:9187,job = postgres,severity = warning` — `alertmanager-ntfy` 1.2.1 colle tous les labels en tags (chaîne `%s = %s` dans le binaire, adjacente à `X-Title`), rendus en hashtags. Non configurable. Et le rétablissement réutilise la description de tir. Voir §2.3 |
| R4 | Les en-têtes ntfy doivent passer par `extraConfigFiles`, le sous-module typé les refuse | **Faux sur le mécanisme, mais la conclusion pratique est pire** (corrigé en r2.1, §0.3) : le sous-module nixpkgs est `freeformType`, donc `settings.ntfy.headers` **s'écrit** sans `extraConfigFiles` — mais `alertmanager-ntfy` 1.2.1 **ne l'applique pas**. Trois formes testées (map, liste `name`/`value`, préfixe `X-`) : config acceptée sans erreur, aucun `click`/`actions` dans le message publié. Il n'existe aucun moyen de poser ces en-têtes par cet outil |
| R5 | Déduire la cause de `systemctl show -p Result,ExecMainStatus` + `journalctl -p warning -n 8` | **Les deux sources sont inopérantes.** (a) au moment utile l'état est déjà écrasé par le redémarrage : `vpn-monitor`, `cf-ddns` et `freeleech-farmer` affichent tous `Result=success ExecMainStatus=0` ; (b) `-p warning` ne remonte que le bruit systemd, et pour `zigbee2mqtt` `-p err` est **vide** — la vraie erreur sort sur stdout donc en priorité `info`. **La bonne source existe et n'est pas utilisée : `$MONITOR_*`.** Voir §3 |
| R6 | Volume « lourd » attribué au formatage | **Le pic est déjà corrigé.** 264 notifications en 27 j, mais **241 (91 %) le 2026-09-02** (n8n 103 à 8 s d'intervalle, unifi 69) : le verrou anti-répétition était alors dans `/tmp`, migré vers `/run` le lendemain (`0a8cbe7`). Depuis : 1 à 4/jour. Il reste un plafond à poser, pas une urgence. Voir §2.5 |

### 0.3 Corrections apportées en r2.1 (constatées en implémentant N2)

| # | Point r2 | Correction |
|---|---|---|
| R7 | `settings.ntfy.headers` permet d'ajouter `Click`/`Actions` aux alertes Alertmanager | **Non.** Banc sur hyper (instance ntfy jetable sur `:18086`, aucun push vers le téléphone) : les trois formes de config sont acceptées sans erreur et **aucune** ne produit de `click`/`actions`. `Click`/`Actions` ne sont donc disponibles que sur le chemin `push_ntfy` (`service-failure`, `backup-verify`, smartd). Cela **renforce** l'arbitrage `ntfy-alertmanager` en N3 : c'est le seul levier restant sur `homelab-alerts` |
| R8 | Action « Silence Alertmanager » sur les notifications | **Infaisable** : ni Alertmanager ni Prometheus ne sont exposés par Traefik (`config.traefik.services` : 24 entrées, aucune des deux), donc le téléphone ne peut pas les joindre. Et les notifications `service-failure` ne viennent pas d'Alertmanager — un silence n'y a aucun sens. Remplacé par `Click` → Glance et une action `view` → Grafana |
| R9 | Ajouter l'en-tête `Markdown` | **Écarté volontairement** : accepté par le serveur (il pose `content_type: text/markdown`) mais le rendu est côté client et n'est pas garanti sur l'app mobile. La mise en forme repose sur texte + emoji, dont le round-trip UTF-8 brut en en-tête HTTP est **vérifié** sur ntfy 2.24 et 2.27 (emoji et tiret cadratin intacts, pas besoin de RFC 2047) |
| R10 | Table de motifs pour isoler la cause | **Un motif de mot seul ment.** Première version validée sur zigbee2mqtt/freeleech, puis prise en défaut sur unifi : `\|-INFO … Setting level of logger [org.mongodb] to ERROR` était présenté comme cause d'un crash. Correction : écarter d'abord toute ligne qui annonce son propre niveau (`INFO`/`DEBUG`/`NOTICE`/`TRACE`), et accepter de n'afficher **aucune** cause plutôt qu'une fausse |

### 0.4 Corrections apportées en r2.2 (constatées en implémentant N3)

| # | Point r2 | Correction |
|---|---|---|
| R11 | Router par sévérité vers deux topics `homelab-critical` / `homelab-warning` | **Remplacé par un routage de priorité, même résultat sans migration.** Ce qui fait sonner le téléphone chez ntfy est la *priorité*, pas le topic ; deux nouveaux topics imposeraient de re-souscrire le téléphone et de re-provisionner les ACL pour aucun gain. Vérifié sur banc : gval lit bien `labels.severity`, et `status == "firing" && labels.severity == "critical" ? "urgent" : "low"` donne priorité **5 / 2 / 2** pour firing-critical, firing-warning et resolved. Aucun changement d'ACL, aucune action sur le téléphone |
| R12 | `ntfy-alertmanager` (xenrox) à arbitrer, « gain non marginal » | **Reporté, avec le coût désormais chiffré : nixpkgs ne fournit que le paquet, pas de module NixOS.** Le remplacement veut dire écrire à la main l'unité systemd, le fichier de conf, le durcissement et le passage des secrets — du code sur mesure sur le chemin le plus critique de la supervision. Les deux bénéfices réels (tags propres, `Click`/`Actions` sur `homelab-alerts`) sont cosmétiques comparés à ça, et le bruit visé par l'arbitrage est déjà traité par R11. **Décision : ne pas remplacer maintenant** ; à reprendre si un module nixpkgs apparaît |
| R13 | `MountPointMissing` inhibe « les alertes restic » | **Périmètre à corriger : `HighDiskUsage` ne doit PAS être inhibé.** `/mnt/usb` absent, les sauvegardes écrivent sur le système de fichiers racine (c'est la motivation même de l'alerte de montage) : un `/` qui se remplit est alors une conséquence **réelle et urgente**, pas du bruit. Cibles retenues : `Restic.*`, `Pgbackrest.*`, `DrillStale`, `SystemdUnitFailed` |

### 0.5 Constat majeur découvert en production (2026-09-29)

**100 % du volume de notifications d'Alertmanager venait d'une seule règle
mal formée.** Les 34 messages présents dans le cache ntfy (fenêtre 12 h) sont
*tous* des `TemperatureHigh`. Ni r1 ni r2 ne l'avaient vu : le diagnostic
initial s'était concentré sur `service-failure`, et le cache ne contenait alors
que 2 messages `homelab-alerts`.

Deux défauts indépendants dans `node_hwmon_temp_celsius > 75` :

- **Par capteur.** coretemp expose 9 séries (package + cœurs). Chacune
  franchissait 75 °C pour son compte, donc un seul épisode thermique produisait
  jusqu'à 9 alertes, chacune avec sa paire firing/resolved. Relevé : 7 capteurs
  distincts dans le cache, `temp1` à lui seul 7 fois.
- **Un seuil unique pour tous les chips.** 75 °C, c'est la charge normale d'un
  i7-9700K (médiane 7 j : **58 °C**, temps passé au-dessus de 75 : **1041 min
  sur 7 j**) et c'est en même temps beaucoup trop permissif pour un NVMe, qui
  throttle vers 80 °C.

Corrigé en N3.13. **Constat indépendant de l'alerting, à traiter comme tel** :
le pic 7 jours de coretemp est **100 °C**, soit Tjunction — ce CPU throttle
vraiment, 323 min au-dessus de 90 °C sur 7 jours. C'est une question de
refroidissement, pas de seuil.

### 0.2 Constats nouveaux (absents de r1)

- **C-A** — Le corps littéral `triggered` a une cause identifiée et une portée
  large : `grep -v ' systemd\[1\]: '` renvoie **0 octet** pour toute unité qui
  ne journalise rien en propre, et ntfy substitue alors son message par défaut
  `triggered`. Classe entière : tout script qui sort en erreur sans écrire sur
  stdout. Cas observé : `vpn-monitor`, composant du dead-man VPN.
- **C-B** — `journalctl -u <svc> -n 30` mélange les invocations : la notification
  de `freeleech-farmer` contenait une traceback alors que le journal courant
  n'affiche que des runs réussis. `$MONITOR_INVOCATION_ID` résout ça exactement.

## 1. Chaîne actuelle

```
unité en échec ──OnFailure──▶ notify-failure@<unité>.service
                                  │ journalctl -u <svc> -n 30 | grep -v systemd[1] | tail -c 3800
                                  ▼
                              push_ntfy  ──curl──▶ ntfy:2586/service-failure
                                                    titre « Homelab Alert », priorité 4

node_exporter (systemd) ──▶ Prometheus ──▶ Alertmanager ──▶ alertmanager-ntfy ──▶ ntfy/homelab-alerts
                            SystemdUnitFailed (for 5m)

restore-drill ──▶ push_ntfy ──▶ ntfy/backup-verify
smartd        ──▶ push_ntfy ──▶ ntfy/homelab-alerts
```

Trois topics, deux formateurs indépendants, aucune notion de gravité côté
`service-failure`, aucun accusé de publication.

## 2. Audit (lecture seule, 2026-09-28)

Méthode : SSH, cache ntfy (`/var/lib/ntfy-sh/cache.db`, rétention 12 h),
journal complet (rétention depuis le 2026-09-01), `grep -a` sur les binaires,
unités systemd transitoires pour les sondes.

### 2.1 Perte silencieuse de publication (le plus grave)

```
14:03:07  cf-ddns.service: Failed with result 'exit-code'   (DNS pas encore up)
14:03:07  cf-ddns.service: Triggering OnFailure= dependencies
14:03:07  Starting Notify ntfy on service failure for cf-ddns.service...
14:03:08  notify-failure@cf-ddns.service.service: Deactivated successfully
14:03:08  Started Push notifications server.                 ← ntfy écoute ICI
```

Le message n'est pas dans le cache ntfy (les 4 autres du jour y sont). Cause :
`push_ntfy` termine par `|| true` avec `-s` et `>/dev/null 2>&1`. Un échec de
publication est **indistinguable d'une absence de panne**.

Portée : systématique au démarrage (toute unité qui échoue avant `ntfy-sh`),
et à chaque `nh os switch` qui redémarre `ntfy-sh`. Aucune reprise.

### 2.2 Illisibilité du topic `service-failure`

Les 4 messages en cache, tous titrés `Homelab Alert`, tous en priorité `4` :

| Heure (UTC) | Service réel | Taille | Contenu |
|---|---|---|---|
| 12:03:22 | zigbee2mqtt | 2839 o | 25 lignes de démarrage, `MQTT failed to connect` noyée au milieu |
| 12:27:41 | zigbee2mqtt | 2839 o | idem, autre boot |
| 14:24:15 | freeleech-farmer | 2854 o | traceback Python, `Connection refused` en fin |
| 15:49:38 | **vpn-monitor** | 9 o | `triggered` — service non identifiable |

Le nom du service n'apparaît **ni dans le titre, ni de façon fiable dans le
corps** : pour `vpn-monitor` l'information est intégralement perdue.

### 2.3 Le topic `homelab-alerts` n'est pas un modèle

Message réel :

```
Titre : Resolved: WAL archiving failures
Corps : archive-push failed at least once in the last hour.
Tags  : green_circle,alertname = PgWalArchiveFailures,
        instance = 127.0.0.1:9187,job = postgres,severity = warning
```

Deux défauts : (a) 4 paires de labels rendues en hashtags sur le téléphone,
comportement câblé dans `alertmanager-ntfy` 1.2.1, non configurable ;
(b) le message de rétablissement annonce la panne (le gabarit `description`
est commun aux deux états).

### 2.4 Couverture croisée des deux canaux

`notify.services` : **73 unités**. `--collector.systemd.unit-include`
(`node.nix:16`) en matche 58. **15 unités hors radar Prometheus** :

```
audiobookshelf      glance                  pgbackrest-metrics      tailscaled
cross-seed          ollama                  pgbackrest-stanza-create unifi
freeleech-farmer    pg-dumpall              podman-bindery          vpn-monitor
                    pgbackrest-default-weekly  qbittorrent  qbittorrent-monitor
```

Conséquences : pour ces 15, `notify-failure` est le seul canal (§2.1) ;
`SystemdUnitFailed` n'émet un `Resolved` que pour les 58 autres ; la
duplication n'existe donc que sur ces 58, et seulement quand l'unité **reste**
en échec 5 min (`for: 5m`). Un oneshot qui échoue puis réussit au run suivant
ne produit qu'une notification.

### 2.5 Volume réel

264 notifications `notify-failure` sur 27 jours :

| Jour | Volume | Détail |
|---|---|---|
| 2026-09-02 | **241** | n8n 103, unifi 69, podman-immich-ml 18, paperless 38, autres 13 |
| 2026-09-16 → 09-28 | 23 | 1 à 4 par jour |

Les 103 notifications n8n du 09-02 sont espacées de **8 secondes** malgré le
verrou de 60 s : le verrou était alors dans `/tmp`, migré vers `/run` le
2026-09-03 (`0a8cbe7`, commit *feat(downloads)*). Verrou vérifié fonctionnel
aujourd'hui (3 fichiers présents, horodatages cohérents).

Risque résiduel : la fenêtre de 60 s autorise encore 60 notifications/heure et
par service pour une unité en boucle de redémarrage lente. Aucun plafond par
incident.

## 3. La source de vérité inutilisée : `$MONITOR_*`

systemd passe à l'`ExecStart` de toute unité déclenchée par `OnFailure=`
(`systemd.exec(5)`) — vérifié sur hyper, systemd 261 :

```
MONITOR_UNIT=cc-f.service        MONITOR_SERVICE_RESULT=exit-code
MONITOR_EXIT_STATUS=42           MONITOR_EXIT_CODE=exited
MONITOR_INVOCATION_ID=510a17ed39614bfc95c760f732af3a0b
```

Ce que ça débloque :

| Variable | Usage | Bug corrigé |
|---|---|---|
| `MONITOR_UNIT` | nom du service dans le titre | titre constant `Homelab Alert` |
| `MONITOR_SERVICE_RESULT` | nature de la panne (`exit-code`, `timeout`, `oom-kill`, `signal`, `core-dump`, `watchdog`, `start-limit-hit`, `resources`, `protocol`, `exec-condition`) | aucune notion de gravité |
| `MONITOR_EXIT_STATUS` | code de sortie ou signal | — |
| `MONITOR_INVOCATION_ID` | `journalctl _SYSTEMD_INVOCATION_ID=…` → **uniquement le run en échec** | bruit de boot (§2.2), mélange d'invocations (C-B) |

Le couple `SERVICE_RESULT` + `EXIT_STATUS` est **toujours** présent : un corps
vide devient structurellement impossible, ce qui élimine le cas `triggered`.

> **Contrainte de conception** : `systemd.exec(5)` précise que ces variables ne
> sont **pas** passées si plusieurs unités partagent la même cible `OnFailure=`.
> Le gabarit `notify-failure@%n.service` (une instance par service) est donc
> *load-bearing* — le remplacer par une unité unique partagée casserait tout.

## 4. Banc LLM (évaluation de P2)

Vrais extraits, modèles présents sur hyper (dont `gemma4:e4b`, tiré le
2026-09-28). Latence mesurée à froid (modèle déchargé, cas réel : ollama
décharge après 5 min d'inactivité) et à chaud :

| Modèle | À froid | À chaud | Qualité sur l'extrait zigbee2mqtt |
|---|---|---|---|
| gemma3:4b | **5,6 s** | 1,3 s | correcte, français seulement si le prompt l'impose strictement |
| qwen3:8b | **21,3 s** | 11,5 s | correcte, mais bloc `Thinking…` déversé sur stdout |
| gemma4:e4b | **46,7 s** | 21,2 s | meilleure formulation, hors budget |

(r1 annonçait 14 s pour qwen3:8b — non reproduit.)

### 4.1 Le problème n'est pas la latence : le modèle ne s'abstient jamais

Trois tests d'adversité sur gemma3:4b, même prompt :

| Entrée | Sortie |
|---|---|
| **vide** (le cas `vpn-monitor`) | *« Cause: Le processus `mon_service.service` a planté, probablement à cause d'un problème de mémoire. Action: Redémarrer le service… »* — nom de service et cause **inventés de rien** |
| logs **sains** (freeleech après reprise) | *« Cause: Plusieurs instances du processus terminent avec succès… Action: Surveiller l'utilisation des ressources »* |
| **bruit seul** (unifi, warnings JVM) | *« Cause: Plusieurs avertissements concernant des méthodes obsolètes »* — un warning inoffensif présenté comme cause racine |

Les deux essais concluants de r1 portaient sur les cas où la cause était
**écrite littéralement** dans le log (`MQTT failed to connect`,
`Connection refused`) — qu'un `grep` trouve aussi. Sur un canal d'alerte, une
cause fabriquée est **pire** qu'un dump brut : rien ne distingue la déduction
de l'invention.

**Conséquence sur le plan** : le LLM ne diagnostique jamais. Il ne peut que
*reformuler* une ligne d'erreur que l'étage déterministe a déjà isolée ; sans
ligne d'erreur, pas d'appel. Toute phrase générée est préfixée `🤖` pour
qu'elle ne soit jamais lue comme un fait. Rétrogradé en **N4, optionnel**.

## 5. Plan

### N1 — Fiabilité (préalable à tout formatage)

1. **`push_ntfy` fiable** (`monitoring/lib/_ntfy.nix`) : lecture de stdin en
   mémoire, 4 tentatives avec backoff (1/2/5/10 s), puis **spool sur disque**
   dans `/var/lib/ntfy-spool/` ; journalisation explicite de l'échec sur
   stderr. La fonction continue de retourner 0 (le spool *est* la réussite) —
   le `set -Eeuo pipefail` du `reportLib` des drills reste intact.
2. **Drain du spool** : `ntfy-spool-drain.timer` (toutes les 2 min, root)
   rejoue les messages en attente, supprime après succès, et publie
   `ntfy_spool_pending` / `ntfy_spool_oldest_age_seconds` /
   `ntfy_publish_failures_total` dans le textfile node_exporter.
3. **Ordonnancement** : `After=ntfy-sh.service` sur `notify-failure@` (ordre
   seul, pas de `Wants=` : éviter un cycle si `ntfy-sh` entrait un jour dans
   `notify.services`).
4. **Alerte sur le canal d'alerte** : `NtfySpoolStuck` (`ntfy_spool_pending > 0`
   pendant 15 min). Le chemin de cette alerte est disjoint du canal en panne
   (Prometheus → Alertmanager → `alertmanager-ntfy`), et reste visible dans
   Grafana/Glance si ntfy est mort.
5. **Fermer les 15 angles morts** : `unit-include` de node_exporter construit
   par union de `config.notify.services` et des motifs actuels (union, pas
   remplacement : les motifs larges couvrent des unités non notifiées —
   `ntfy`, `restic-verify`, `postgres-restore-drill`, `btrfs-scrub`).

### N2 — Lisibilité

6. **Titre** depuis `$MONITOR_*` : `❌ cf-ddns — exit-code 1`,
   `⏱ immich-server — timeout`, `💀 n8n — oom-kill`,
   `🔁 unifi — start-limit-hit`.
7. **Corps** : 3 à 8 lignes tirées de
   `journalctl _SYSTEMD_INVOCATION_ID=$MONITOR_INVOCATION_ID`, sélectionnées
   par table de motifs (`Connection refused`, `Address already in use`,
   `Permission denied`, `No space left`, `Read-only file system`,
   dernière ligne de traceback, dernière ligne `error:`/`ERROR`), repli sur
   `SERVICE_RESULT` + `EXIT_STATUS` + les 3 dernières lignes. Plafond 800 o.
8. **En-têtes ntfy** : `Click` → Glance (`https://home.<host>.<domaine>`),
   `Actions` → `view, Grafana, …`. Pas de silence Alertmanager (R8), pas de
   `Markdown` (R9), pas d'`Icon` (il faudrait héberger une image). **Priorité
   par gravité** : `oom-kill`/`core-dump`/`watchdog` → `urgent` ;
   `exec-condition` → `low` ; tout le reste → `high`. Volontairement pas de
   `default` généralisé : à 1-4 notifications par jour, le levier sur le volume
   est N3 (routage + plafond), pas la mise en sourdine d'échecs réels.
9. **Gabarits Alertmanager distincts** pour `firing` et `resolved` (corriger
   « Resolved: … » qui annonce la panne, §2.3).

### N3 — Volume et routage

10. **`inhibit_rules`** — 4 règles, volontairement étroites (une inhibition
    trop large transforme un canal bruyant en canal aveugle) :
    `MountPointMissing` → `Restic.*|Pgbackrest.*|DrillStale|SystemdUnitFailed`
    (sans `equal` : la cause et les cibles n'ont aucun label comparable, et
    `HighDiskUsage` est exclu, cf. R13) ; `HostOOMKill` →
    `MemoryStallSustained|HighMemoryPressure` (`equal: instance`) ;
    `VpnTunnelDown` → `VpnListenerUnbound` (`equal: instance`) ;
    `ProbeFailure` → `TraefikHigh5xxRate` (sans `equal` : cette dernière est une
    somme sans label).
    `ServiceDown` n'inhibe rien : quand une cible tombe, les alertes qui lisent
    ses métriques deviennent *sans données* et ne tirent pas — il n'y a rien à
    inhiber. Et `QbittorrentUploadThrottled` ne dépend pas du tunnel : c'est le
    plafond d'upload, pas la connectivité.
11. **Priorité par sévérité** plutôt que deux topics (R11) : firing+critical →
    `urgent`, tout le reste → `low`, donc les avertissements atterrissent
    silencieusement dans l'historique du topic. Le titre porte aussi la
    sévérité (`🚨` / `⚠️` / `✅ Rétabli`). Pour rendre les avertissements
    audibles, un seul mot à changer (`low` → `default`).
13. **`TemperatureHigh` remplacée** (ajout hors plan initial, cf. §0.5) par
    `CpuTemperatureHigh` (`max by (chip)` sur `platform_coretemp.*|thermal_.*`,
    > 90 °C) et `NvmeTemperatureHigh` (`max by (chip)` sur `nvme.*`, > 85 °C),
    les deux avec `for = 10m` et `keep_firing_for = 30m`. `max by (chip)`
    ramène un épisode à une alerte par chip au lieu de 9 ; `keep_firing_for`
    (Prometheus 3.14 ici, champ disponible depuis 2.42) supprime la paire
    resolved/firing que l'oscillation autour du seuil produisait toutes les
    quelques minutes. Seuils dimensionnés sur 7 jours d'historique local pour
    continuer à tirer sur les vrais épisodes (coretemp : 323 min > 90 °C ;
    NVMe : 69 min > 85 °C, pic 89,9 °C).

12. **Plafond par incident** dans `notify-failure`, en remplacement du verrou
    plat de 60 s : notification immédiate, puis au plus une toutes les 5 min,
    puis une toutes les 30 min, chacune portant le nombre d'échecs qu'elle
    résume (`(×38)` dans le titre, `🔁 38 échecs en 5min` dans le corps). Une
    heure de calme clôt l'incident, pour qu'un échec isolé ultérieur redevienne
    immédiat au lieu d'hériter du palier de 30 min.

### N4 — Reformulation LLM (optionnel, après N1-N3)

13. Étage 2 seulement, sur une ligne d'erreur déjà isolée par N2.
    gemma3:4b, API ollama (`think: false`), `keep_alive` long, timeout 8 s,
    repli déterministe silencieux, préfixe `🤖`.

### Écarté

- **Loki/Alloy** (retirés le 2026-09-27) : réintroduire la brique pour un
  bouton « Logs » coûte plus que le gain ; `$MONITOR_INVOCATION_ID` donne déjà
  le bon extrait.
- **n8n comme enrichisseur** : dépendance d'un canal critique à un service qui
  est lui-même le premier générateur d'alertes (§2.5).
- **`ntfy-alertmanager` (xenrox, 1.0.1)** : arbitré en N3 et **reporté** (R12).
  C'est bien le seul levier restant sur `homelab-alerts` — tags propres,
  `Click`/`Actions` qu'`alertmanager-ntfy` ne sait pas poser (R7) — mais nixpkgs
  n'en fournit que le paquet : pas de module NixOS, donc unité systemd, conf,
  durcissement et secrets à écrire à la main sur le chemin le plus critique de
  la supervision. Bénéfice cosmétique, coût structurel. À reprendre si un module
  apparaît dans nixpkgs.

## 6. Ordre d'exécution

| Lot | Contenu | Dépendances | Risque |
|---|---|---|---|
| N1 | 1-5 | aucune | faible (aucun changement de format) |
| N2 | 6-9 | N1.1 (le spool sérialise les en-têtes) | faible |
| N3 | 10-12 | N2.8 (sévérité) | moyen (inhibitions = risque de masquer) |
| N4 | 13 | N2.7 | faible (repli déterministe) |

## 7. Journal d'application

| Date | Lot | Contenu | Validation |
|---|---|---|---|
| 2026-09-29 | **N1** | `_ntfy.nix` : 4 tentatives (0/1/2/5 s, `curl -f -m 5`) puis spool `/var/lib/ntfy-spool` ; `push_ntfy` retourne toujours 0. `notification.nix` : `ntfy-spool-drain.{service,timer}` (2 min + `OnBootSec`), tmpfiles `1733`, `After=ntfy-sh.service` sur `notify-failure@`, drain ajouté à `notify.services`. `node.nix` : `unit-include` = union motifs ∪ `notify.services` (sous-ensembles déjà couverts filtrés) → 46 alternatives, **les 15 angles morts fermés**. `prometheus-alerts.nix` : `NtfySpoolStuck` (critical, 15 min) + `NtfySpoolDrainMissing` (fraîcheur, pas `absent()`). | `nix flake check --all-systems` OK · shellcheck OK sur les 2 scripts générés · **banc de bout en bout sur hyper** (faux collecteur HTTP, aucun déploiement) : publication directe (en-têtes `Title`/`Priority`/`Tags` + corps exacts, 0 spool) ; collecteur coupé → 8 s de reprise puis 1 fichier spoolé, préambule 4 lignes + séparateur conforme ; appelant sous `set -Eeuo pipefail` **survit** au chemin spool (cas du `trap` des drills) ; drain collecteur coupé → rc=0, rien perdu, `ntfy_spool_pending 2` ; drain collecteur rétabli → 2 messages rejoués **à l'identique** (corps vide compris, `body_len 0`), spool vidé, métriques à 0. Drop-box `1733` vérifié : `postgres` crée+renomme, ne peut **pas** lister, root lit+supprime. |

| 2026-09-29 | **N2** | `_ntfy.nix` : bloc d'en-têtes « une ligne = un en-tête HTTP » (le format du spool est désormais celui de `curl`, un en-tête de plus ne change plus le format), `NTFY_CLICK`/`NTFY_ACTIONS`. `notification.nix` : `notify-failure@` réécrit sur `$MONITOR_*` — titre `<glyphe> <service> — <résultat> <code>`, corps scopé par `$MONITOR_INVOCATION_ID`, ligne cause = dernière ligne diagnostique après exclusion des lignes `INFO`/`DEBUG`/`NOTICE`/`TRACE`, dédoublonnée du contexte, ANSI retiré, 200 o/ligne avec `…` et `iconv -c`, repli non vide sur `RESULT`+`STATUS` ; priorité par gravité ; drain adapté au nouveau format. `alertmanager.nix` : gabarits `firing`/`resolved` distincts, rétabli en priorité `low`. | `nix flake check --all-systems` OK · toplevel hyper construit · shellcheck OK · **banc sur invocations réelles du 2026-09-28** (ntfy jetable `:18086`, aucun push vers le téléphone) : zigbee2mqtt → cause `MQTT failed to connect` extraite de 25 lignes de démarrage ; freeleech-farmer → `urllib.error.URLError … Connection refused` (dernière ligne du traceback) ; cf-ddns → l'erreur DNS, troncature signalée `…` ; unifi → **aucune** ligne cause (le faux positif `INFO … to ERROR` est écarté) ; vpn-monitor sans sortie → `Aucune sortie journalisée … Résultat systemd : exit-code 1` au lieu de `triggered` ; `oom-kill` → 💀 priorité 5 ; `exec-condition` → ⏭ priorité 2. **Corps : 247-437 o contre 2839-2854 o avant.** Aller-retour spool vérifié : titre emoji, `Click` et `Actions` intacts après rejeu. Gabarits Alertmanager testés bout en bout (webhook `firing` → `🔴 …`, `resolved` → `✅ Rétabli : …` priorité 2, plus de description de panne dans le message de reprise). |

| 2026-09-29 | **N3** | `alertmanager.nix` : 4 `inhibit_rules` (§5.10), priorité `status == "firing" && labels.severity == "critical" ? "urgent" : "low"`, titre portant la sévérité (`🚨`/`⚠️`/`✅ Rétabli`). `notification.nix` : plafond par incident à paliers 0 / 5 min / 30 min dans `notify-failure`, état dans `/run/notify-failure-<unité>.state` (`last count stage since`), clôture d'incident après 1 h de calme, compte reporté dans le titre (`(×N)`) et dans le corps. | `nix flake check --all-systems` OK · toplevel hyper construit · **`amtool check-config` sur la config générée : SUCCESS, 4 inhibit rules**, `equal: [instance]` bien présent sur les deux règles concernées · gval `labels.severity` validé sur banc (priorités 5/2/2) · **tempête du 2026-09-02 rejouée** (113 échecs à 8 s d'intervalle, horloge simulée) → **2 notifications au lieu de 113**, la seconde titrée `❌ n8n — exit-code 1 (×38)` avec `🔁 38 échecs en 5min` · 6 paliers vérifiés un par un : échec isolé immédiat, +30 s retenu, +5 min 01 notifié `(×2)`, +10 min retenu, +40 min notifié, +1 h 05 après la dernière notification → incident clos et notification immédiate sans compteur. |

| 2026-09-29 | **N3.13** | `prometheus-alerts.nix` : `TemperatureHigh` (par capteur, tous chips, > 75 °C) remplacée par `CpuTemperatureHigh` (> 90 °C) et `NvmeTemperatureHigh` (> 85 °C), agrégées en `max by (chip)`, `for = 10m` + `keep_firing_for = 30m`. | `promtool check rules` sur les règles générées : **SUCCESS, 39 rules** · les deux expressions évaluées contre les données live de Prometheus : aucune série (pas en alerte à l'instant, conforme) · réduction mesurée du temps en alerte : **1041 min → 323 min sur 7 j** pour coretemp, et un épisode donne désormais **1 alerte au lieu de 9**. |

### Reste à faire sur N1-N3

- Déployer (`nh os switch`) puis vérifier `systemctl list-timers ntfy-spool-drain`
  et la présence de `ntfy_spool_*` dans `/var/lib/node-exporter-textfile/`.
- Après le prochain boot, vérifier que `cf-ddns` (qui échoue faute de DNS) donne
  bien une notification — c'est le cas de régression de §2.1.
- Vérifier sur le téléphone que le tap ouvre bien Glance et que le bouton
  « Grafana » apparaît (les en-têtes sont validés côté serveur, le rendu est
  côté client).
- Les alertes `homelab-alerts` restent sans `Click`/`Actions` et avec les tags
  pollués : arbitré et reporté (R12), rien à faire côté déploiement.
- Après déploiement, les anciens fichiers `/run/notify-failure-*.lock` sont
  orphelins (le nouvel état est `.state`) ; ils disparaissent au reboot,
  `/run` étant un tmpfs.
- Vérifier sur le téléphone qu'un avertissement arrive bien **sans son** et
  qu'une alerte critique reste insistante.
- **Hors alerting** : le CPU passe 323 min sur 7 jours au-dessus de 90 °C et
  touche 100 °C (Tjunction). À regarder côté refroidissement — aucun seuil ne
  règle ça.
