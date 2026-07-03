# Architecture des backups (hôte hyper)

Vue d'ensemble de la stratégie de sauvegarde : quoi, où, comment, et pourquoi.
Pour **restaurer** ou vérifier, voir [restore-drill.md](restore-drill.md).

## Principe

Un module restic maison (`modules/features/storage/restic.nix`) expose l'option
`backups.sources.<nom>`. Chaque source déclare des `paths` et est sauvegardée vers
plusieurs **cibles** (repos), donnant un job systemd `restic-backups-<source>-<cible>`
par couple (timer quotidien ~02:05).

### Cibles (repos)

| Cible | Emplacement | Nature |
|---|---|---|
| `s3` | `s3:https://s3.hyper.logikdev.fr` (rustfs) | sur site, store objet |
| `usb` | `/mnt/usb` | sur site, disque externe |
| `hetzner` | `sftp:…@…your-storagebox.de:/home` | **offsite** (Storage Box, trafic gratuit) |
| `local` | `/mnt/local` | sur site (certaines sources) |

Par défaut une source va sur `s3 + usb + hetzner`. Rétention (prune auto) :
`--keep-daily 7 --keep-weekly 3 --keep-monthly 6 --keep-yearly 2`.
Secrets : `restic.env` (mot de passe restic + creds S3), clé SSH Hetzner dans agenix.

## Cas particuliers (importants)

### Immich (~440 Go de médias)
Source `immich` → `s3 + usb + hetzner`. Les photos ont donc une **copie offsite
directe** (`immich-hetzner`). C'est le gros volume de la box Hetzner.

### rustfs (~485 Go) — **usb uniquement, PAS hetzner**
Le volume rustfs contient tous les repos `*-s3` (dont `immich-s3` ≈ 439 Go) **et**
`pg-backups`. Source `rustfs` → **usb seulement** (snapshot LVM `/mnt/snap-ultra/rustfs`
pour la cohérence). On ne l'envoie **pas** à Hetzner : ça dupliquerait Immich offsite
(≈ 880 Go sur une box de 1 To). Le blob-store est ainsi protégé localement sur usb.

### PostgreSQL — deux mécanismes complémentaires
Postgres porte les joyaux (coffre **Vaultwarden**, prowlarr, métadonnées Immich,
authelia, *arr). Deux backups distincts :

1. **barman — primaire sur site, PITR.** Archivage WAL continu + base backup hebdo
   (dim. 03:00, rétention `REDUNDANCY 8`) → `s3://pg-backups/pg-16` (rustfs).
   `pg-backups` ≈ 24 Go. Permet un point-in-time recovery fin. Mais **sur site
   uniquement** (dans rustfs, qui ne part pas offsite).
2. **pg_dumpall — copie offsite logique.** Dump complet du cluster (rôles + toutes
   les bases, ~960 Mo / ~340 Mo compressé) écrit dans `/mnt/ultra/pg-dump/pg-dumpall.sql`
   (nom fixe, écrasé → pas d'accumulation), puis restic → **hetzner + usb**.
   Défini dans `postgresql.nix` via `backups.sources.pg-dump` (runBefore = le dump).
   Restauration triviale (`psql`/`pg_restore`), **sans avoir à remonter un S3** —
   idéal en désastre. C'est ce qui donne le vrai 3-2-1 aux bases.

## Résumé 3-2-1

| Donnée | Sur site | Offsite (Hetzner) |
|---|---|---|
| Configs services (vaultwarden files, *arr, zigbee, grafana, adguard, unifi…) | s3 + usb (+local) | ✅ |
| Immich (médias) | s3 (rustfs) + usb | ✅ direct |
| rustfs (blob-store = s3 repos + pg-backups) | usb | ❌ (volontaire, cf. above) |
| Postgres (bases) | barman (rustfs, PITR) | ✅ dump logique |

## Supervision & vérification

- **Exporters Prometheus** : un `prometheus-restic-exporter-<source>-<cible>` par repo
  (`modules/features/monitoring/restic.nix`) → âge/taille des snapshots dans Grafana.
- **Drills hebdo** (`modules/features/monitoring/restore-drill.nix`, topic ntfy
  `backup-verify`) : intégrité de tous les repos, restore canary offsite (zigbee),
  et restore Postgres réel depuis barman. Détails + procédures manuelles :
  [restore-drill.md](restore-drill.md).
