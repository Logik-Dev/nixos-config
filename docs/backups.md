# Architecture des backups (hôte hyper)

Vue d'ensemble de la stratégie de sauvegarde : quoi, où, comment, et pourquoi.
Pour **restaurer** ou vérifier, voir [restore-drill.md](restore-drill.md).

## Principe

Un module restic maison (`modules/features/storage/restic.nix`) expose l'option
`backups.sources.<nom>`. Chaque source déclare des `paths` et est sauvegardée vers
plusieurs **cibles** (repos), donnant un job systemd `restic-backups-<source>-<cible>`
par couple (timer quotidien ~02:05).

### Cibles (repos restic)

| Cible | Emplacement | Nature |
|---|---|---|
| `usb` | `/mnt/usb` | sur site, disque externe |
| `hetzner` | `sftp:…@…your-storagebox.de:/home` | **offsite** (Storage Box, trafic gratuit) |
| `local` | `/mnt/local` | sur site (certaines sources) — **LV du disque système**, pas un domaine de panne distinct |

Par défaut une source va sur `usb + hetzner`. Rétention (prune auto) :
`--keep-daily 7 --keep-weekly 3 --keep-monthly 6 --keep-yearly 2`.
Secrets : `restic.env` (mot de passe restic), clé SSH Hetzner dans agenix.
**Copie de secours du mot de passe restic dans Vaultwarden** (comme la
passphrase pgBackRest) : sans elle, les repos sont illisibles si l'identité
age maître est perdue.

> **Historique — rustfs (décommissionné 2026-07-04).** Il y avait une cible `s3`
> (store objet rustfs sur `/mnt/ultra`). Elle a été retirée : le blob-store
> vivait sur le **même disque** que les sources (protégeait seulement contre la
> suppression accidentelle — usb/hetzner couvrent déjà ça), dupliquait ~440 Go
> d'Immich sur l'USB via son propre backup, et son seul autre contenu (le store
> barman) est remplacé par pgBackRest. Données gelées jusqu'à ~2026-07-18 :
> `/mnt/ultra/rustfs` et `/mnt/usb/restic/rustfs`, puis suppression manuelle.

## Cas particuliers (importants)

### Immich (~440 Go de médias)
Source `immich` → `usb + hetzner`. Avec le live, ça fait 3 copies, 2 supports,
1 offsite — le 3-2-1 canonique.

### PostgreSQL — pgBackRest (PITR) + dump logique
Postgres porte les joyaux (coffre **Vaultwarden**, prowlarr, métadonnées Immich,
authelia, *arr). Deux mécanismes complémentaires :

1. **pgBackRest — primaire, PITR, on-site ET offsite.** Archivage WAL continu
   (asynchrone, spool) + base backup full hebdo (dim. 03:30, rétention 8 fulls)
   vers **deux repos chiffrés aes-256-cbc** : `repo1` = `/mnt/usb/pgbackrest`
   (posix) et `repo2` = Storage Box Hetzner (sftp) → **PITR offsite**.
   Module : `modules/features/storage/pgbackrest.nix`. Passphrase de chiffrement
   dans agenix (`pgbackrest.env`) **et en copie dans Vaultwarden** — sans elle,
   repos illisibles. Attention : la box **bannit l'IP** en cas d'excès de
   connexions (archive-push limité à 1 process pour ça).
2. **pg_dumpall — filet logique de dernier recours.** Dump complet du cluster
   (rôles + toutes les bases, ~960 Mo) écrit dans `/mnt/ultra/pg-dump/pg-dumpall.sql`
   (nom fixe, écrasé), puis restic → **hetzner + usb**. Restauration avec psql
   seul — aucune dépendance à pgBackRest ni à sa passphrase.

(barman-cloud → rustfs, l'ancien mécanisme PITR on-site only, a été remplacé par
pgBackRest le 2026-07-04 ; son store reste gelé dans `/mnt/ultra/rustfs/pg-backups`
jusqu'à ~2026-07-18.)

## Résumé 3-2-1

| Donnée | Sur site | Offsite (Hetzner) |
|---|---|---|
| Configs services (vaultwarden files, *arr, zigbee, grafana, adguard, unifi…) | usb (+local) | ✅ |
| Immich (médias) | usb | ✅ direct |
| Postgres (bases) | pgBackRest repo1 (usb, PITR) | ✅ pgBackRest repo2 (**PITR**) + dump logique |

## Supervision & vérification

- **Exporters Prometheus** : un `prometheus-restic-exporter-<source>-<cible>` par repo
  (`modules/features/monitoring/restic.nix`) → âge/taille des snapshots dans Grafana.
- **Drills hebdo** (`modules/features/monitoring/restore-drill.nix`, topic ntfy
  `backup-verify`) : intégrité de tous les repos restic, restore canary offsite
  (zigbee ← Hetzner), restore Postgres réel **pgBackRest ← Hetzner**, et read-data
  tournant sur les gros repos. Détails + procédures manuelles :
  [restore-drill.md](restore-drill.md).
