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

### rustfs (~470 Go) — **non sauvegardé en bloc (volontaire)**
Le volume rustfs est le blob-store S3 : il contient tous les repos `*-s3` (dont
`immich-s3` ≈ 440 Go) **et** `pg-backups` (barman, ≈ 24 Go). On **ne le sauvegarde
plus intégralement** : chaque repo `*-s3` a déjà sa propre copie `-usb`/`-hetzner`
directe, donc un backup `rustfs-usb` revenait à stocker ~440 Go d'Immich en double
sur le même disque USB (≈ 860 Go d'Immich sur l'USB). Immich est protégé en direct
via `backups.sources.immich` (usb + hetzner). La **seule** donnée qui ne vivait que
dans rustfs — le store barman — est sauvegardée à part, cf. ci-dessous.

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
3. **pg-barman — copie USB du store PITR.** Le store barman (`/mnt/ultra/rustfs/pg-backups`,
   ≈ 24 Go) ne vit que dans rustfs. Depuis l'abandon du backup `rustfs-usb` en bloc,
   une mini-source `backups.sources.pg-barman` (usb only, `postgresql.nix`) sauvegarde
   *juste* ce store → la capacité PITR survit à une perte du disque rustfs, sans traîner
   les ~440 Go d'Immich. Lecture live (pas de snapshot) : objets barman write-once.

## Résumé 3-2-1

| Donnée | Sur site | Offsite (Hetzner) |
|---|---|---|
| Configs services (vaultwarden files, *arr, zigbee, grafana, adguard, unifi…) | s3 + usb (+local) | ✅ |
| Immich (médias) | s3 (rustfs) + usb | ✅ direct |
| rustfs (blob-store = s3 repos + pg-backups) | — (non sauvé en bloc, cf. above) | ❌ (volontaire) |
| Postgres (bases) | barman (rustfs, PITR) + `pg-barman` (usb) | ✅ dump logique |

## Supervision & vérification

- **Exporters Prometheus** : un `prometheus-restic-exporter-<source>-<cible>` par repo
  (`modules/features/monitoring/restic.nix`) → âge/taille des snapshots dans Grafana.
- **Drills hebdo** (`modules/features/monitoring/restore-drill.nix`, topic ntfy
  `backup-verify`) : intégrité de tous les repos, restore canary offsite (zigbee),
  et restore Postgres réel depuis barman. Détails + procédures manuelles :
  [restore-drill.md](restore-drill.md).
