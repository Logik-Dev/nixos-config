# Architecture des backups (hôte hyper)

Vue d'ensemble de la stratégie de sauvegarde : quoi, où, comment, et pourquoi.
Pour **restaurer** ou vérifier, voir [restore-drill.md](restore-drill.md).

## Principe

Un module restic maison (`modules/features/storage/restic.nix`) expose l'option
`backups.sources.<nom>`. Chaque source déclare des `paths` et est sauvegardée vers
**deux cibles** (usb + hetzner), via **une seule unité systemd par source**
`restic-backups-<source>` (timer quotidien ~02:05) qui enchaîne les deux repos.

### Cibles (repos restic)

| Cible | Emplacement | Nature |
|---|---|---|
| `usb` | `/mnt/usb` | sur site, disque externe |
| `hetzner` | `sftp:…@…your-storagebox.de:/home` | **offsite** (Storage Box, trafic gratuit) |

Rétention (prune auto) :
`--keep-daily 7 --keep-weekly 3 --keep-monthly 6 --keep-yearly 2`.
Secrets : `restic.env` (mot de passe restic), clé SSH Hetzner dans agenix.
**Copie de secours du mot de passe restic dans Vaultwarden** (comme la
passphrase pgBackRest) : sans elle, les repos sont illisibles si l'identité
age maître est perdue.

> **Historique — cible `local` (retirée 2026-09-27).** `/mnt/local` était un LV
> du **disque système** : pas un domaine de panne distinct. `usb + hetzner` la
> remplacent (une copie sur site, une offsite).

## Sources sauvegardées

`backups.sources.<nom>` (module `modules/features/storage/restic.nix`) :

| Source | Emplacement | Cibles |
|---|---|---|
| `adguard` | `/var/lib/private/AdGuardHome` | usb + hetzner |
| `grafana` | état Grafana | usb + hetzner |
| `immich` | `/mnt/ultra/immich` (hors `cache/`,`thumbs/`,`encoded-video`) | usb + hetzner |
| `jellyfin` | `/mnt/ultra/jellyfin` (hors `log/`,`cache/`,`transcodes`) | usb + hetzner |
| `mealie` | `/var/lib/private/mealie` | usb + hetzner |
| `mosquitto` | `/var/lib/mosquitto` | usb + hetzner |
| `n8n` | `/var/lib/private/n8n` | usb + hetzner |
| `paperless` | `/mnt/local/paperless` | usb + hetzner |
| `pg-dump` | `/mnt/ultra/pg-dump` (pg_dumpall 01:30) | usb + hetzner |
| `prowlarr` / `radarr` / `sonarr` | `/mnt/ultra/<app>` | usb + hetzner |
| `qbittorrent` | profil + état | usb + hetzner |
| `rankoder` | `/var/lib/rankoder` (état seul, pas le retentionDir) | usb + hetzner |
| `sabnzbd` | `/var/lib/sabnzbd` | usb + hetzner |
| `seerr` | `/var/lib/private/jellyseerr` | usb + hetzner |
| `traefik` | `acme.json` (copie live) | usb + hetzner |
| `unifi` | `/var/lib/unifi/data/backup/autobackup` (`.unf`) | usb + hetzner |
| `vaultwarden` | `/var/lib/vaultwarden` (+ postgres) | usb + hetzner |
| `zigbee2mqtt` | state z2m (`database.db`, coordinator) | usb + hetzner |

## Non sauvegardées (assumé)

- **Syncthing** : les folders sont déclaratifs (repris à neuf au déploiement),
  les certificats vivent dans agenix ; rien d'unique à sauvegarder.
- **sonicmaster** : l'hôte est offline depuis des mois, volontairement non
  supervisé **et** non sauvegardé (cf. `hosts/sonicmaster/configuration.nix`).
- **Dossier `consume` Paperless** (`/mnt/local/paperless/consume`) : inbox
  Syncthing 777, transitoire (Paperless consomme puis supprime).

> **Historique — rustfs (décommissionné 2026-07-04).** L'ancienne cible `s3`
> (store objet rustfs sur `/mnt/ultra`) a été retirée (blob-store sur le même
> disque que les sources, ~440 Go dupliqués). `usb + hetzner` la remplacent.

## Cas particuliers (importants)

### Immich (~480 Go de médias)
Source `immich` → `usb + hetzner`. Avec le live, ça fait 3 copies, 2 supports,
1 offsite — le 3-2-1 canonique.

### PostgreSQL — pgBackRest (PITR) + dump logique
Postgres porte les joyaux (coffre **Vaultwarden**, prowlarr, métadonnées Immich,
authelia, *arr). Deux mécanismes complémentaires :

1. **pgBackRest — primaire, PITR, on-site ET offsite.** Archivage WAL continu
   (asynchrone, spool) + base backup full hebdo (dim. 03:30, rétention 8 fulls)
   vers **deux repos chiffrés aes-256-cbc** : `repo1` = `/mnt/usb/pgbackrest`
   (posix) et `repo2` = Storage Box Hetzner (sftp) → **PITR offsite**.
   Module : `modules/features/storage/pgbackrest/`. Passphrase de chiffrement
   dans agenix (`pgbackrest.env`) **et en copie dans Vaultwarden** — sans elle,
   repos illisibles. Attention : la box **bannit l'IP** en cas d'excès de
   connexions (archive-push limité à 1 process pour ça).
2. **pg_dumpall — filet logique de dernier recours.** Dump complet du cluster
   (rôles + toutes les bases, ~960 Mo) écrit dans `/mnt/ultra/pg-dump/pg-dumpall.sql`
   (nom fixe, écrasé), puis restic → **hetzner + usb**. Restauration avec psql
   seul — aucune dépendance à pgBackRest ni à sa passphrase.

## Résumé 3-2-1

| Donnée | Sur site | Offsite (Hetzner) |
|---|---|---|
| Configs services (vaultwarden files, *arr, zigbee, grafana, adguard, unifi…) | usb | ✅ |
| Immich (médias) | usb | ✅ direct |
| Postgres (bases) | pgBackRest repo1 (usb, PITR) | ✅ pgBackRest repo2 (**PITR**) + dump logique |

## Supervision & vérification

- **Métriques Prometheus (push)** : chaque unité de backup écrit, après un
  succès, `restic_backup_timestamp` / `restic_snapshots_total` /
  `restic_backup_size_total` par repo dans le textfile de node_exporter
  (`/var/lib/node-exporter-textfile`, helper `monitoring/lib/_restic-metrics.nix`)
  → âge/taille des snapshots dans Grafana. Plus aucun process exporter à poller
  les repos sftp (l'ancien modèle « un exporter par repo » saturait le
  rate-limiter de la Storage Box). L'alerte `ResticMetricsMissing` (dead-man)
  couvre une unité de backup qui ne tourne plus.
- **Drills hebdo** (`modules/features/monitoring/restore-drill/`, topic ntfy
  `backup-verify`) : `restic-verify` (intégrité de tous les repos + `--read-data`
  des petits, `--read-data-subset=10%` pour immich, puis restore canari offsite
  zigbee ← Hetzner) et `postgres-restore-drill` (restore Postgres réel
  **pgBackRest ← Hetzner**). Détails + procédures manuelles :
  [restore-drill.md](restore-drill.md).
