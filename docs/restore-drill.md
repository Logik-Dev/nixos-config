# Restore drill — vérification & restauration des backups

Ce document couvre (1) les vérifications **automatiques** hebdomadaires et (2) les
procédures **manuelles** de restauration. Objectif : prouver que les backups sont
réellement restaurables, pas seulement qu'ils tournent.

Architecture backup : chaque source restic est sauvegardée vers plusieurs cibles
(`usb`, `hetzner` offsite, parfois `local`). Postgres est sauvegardé à part par
**pgBackRest** (base backup hebdo + archivage WAL continu, PITR) vers deux repos
chiffrés : `/mnt/usb/pgbackrest` (repo1) et la Storage Box Hetzner en sftp
(repo2, **PITR offsite**).

## Ordre de priorité (joyaux)

1. **Vaultwarden** — coffre dans Postgres (`vaultwarden`) + `rsa_key.pem`/pièces jointes dans `/var/lib/vaultwarden` (restic).
2. **Zigbee2mqtt** — `database.db` + `coordinator_backup.json` (restic) ; sans ça, ré-appairage complet.
3. **Postgres** — porte aussi prowlarr, immich (métadonnées), etc.
4. **Immich** — 440 Go de médias (restic : rustfs + usb + hetzner).

---

## 1. Vérifications automatiques (hebdo, dimanche)

Module : `modules/features/monitoring/restore-drill.nix`. Résultats postés (succès **et**
échec, en heartbeat) sur le topic ntfy **`backup-verify`**.

| Service systemd | Quand | Ce qu'il prouve |
|---|---|---|
| `restic-check` | dim. 09:00 | `restic check` structurel sur **tous** les repos + `--read-data` (blobs réels) sur tout sauf `immich`/`rustfs` (couverts par `restic-read-data`) — `--retry-lock 30m` |
| `restore-canary` | dim. 10:00 | Restore réel de **Zigbee depuis Hetzner** (offsite) → `PRAGMA integrity_check` (échoue si `coordinator_backup.json` manquant) |
| `postgres-restore-drill` | dim. 11:00 | Contrôle d'âge (< 9 j) + `pgbackrest check` repo2, puis restore réel **depuis Hetzner (repo2)** → instance jetable → requêtes sur vaultwarden/prowlarr |
| `restic-read-data` | dim. 12:00 | `--read-data` **par slice tournante** `N/13` (dérivée de la semaine ISO) sur les gros repos immich ×3 + rustfs-usb → couverture complète tous les ~13 cycles — `--retry-lock 30m` |

Lancer un drill à la main :

```sh
systemctl start postgres-restore-drill.service
journalctl -u postgres-restore-drill.service -f
```

> **Gros repos (`immich` ~440 Go, `rustfs` ~485 Go)** : trop volumineux pour un
> `--read-data` complet hebdo. `restic-check` ne fait qu'un contrôle structurel dessus ;
> la vérification des blobs est faite par `restic-read-data` en **slice tournante `N/13`**
> (restic impose `t ≤ 256`), soit ~1/13 relu chaque semaine → couverture totale par
> trimestre. Trafic Hetzner gratuit ; coût = ~1/13 de la bande passante + I/O disque local.

---

## 2. Procédures manuelles

`restic` et `pgbackrest` sont dans le PATH système. Les binaires serveur postgres
non (chemins nix store) — récupérer le chemin courant :

```sh
PG=$(dirname "$(readlink -f "$(systemctl show postgresql.service -p ExecStart --value \
  | grep -o '/nix/store/[^ ]*/bin/postgres' | head -1)")")
```

Les creds sont dans agenix (`root` uniquement) : `/run/agenix/restic.env` (restic)
et `/run/agenix/pgbackrest.env` (passphrases de chiffrement des repos pgBackRest —
**copie de secours dans Vaultwarden**).

### 2a. Restore fichier restic (n'importe quelle source / cible)

```sh
set -a; . /run/agenix/restic.env; set +a

# Repos possibles pour une source <SRC> :
#   s3:https://s3.hyper.logikdev.fr/restic/<SRC>        (rustfs)
#   /mnt/usb/restic/<SRC>                                (usb)
#   sftp:u625917@u625917.your-storagebox.de:/home/restic/<SRC>  (hetzner offsite)
#   /mnt/local/restic/<SRC>                              (local, certaines sources)
REPO=sftp:u625917@u625917.your-storagebox.de:/home/restic/vaultwarden

restic -r "$REPO" snapshots                  # lister
restic -r "$REPO" restore latest --target /mnt/ultra/restore-test/vw
# ou un seul fichier :
restic -r "$REPO" restore latest --target /tmp/x --include /var/lib/vaultwarden/rsa_key.pem
```

Restauration **en place** (après sinistre) : arrêter le service, restaurer sur `/`,
vérifier les droits, redémarrer :

```sh
systemctl stop vaultwarden
restic -r "$REPO" restore latest --target /            # restaure les chemins absolus
systemctl start vaultwarden
```

### 2b. Restore Postgres (pgBackRest → instance jetable, non destructif)

Procédure validée par `postgres-restore-drill`. Restaure vers un `PGDATA` scratch et
démarre une instance **isolée** (port 5433, socket dédiée, archivage coupé) — ne touche
jamais l'instance live. `--repo=1` = USB, `--repo=2` = Hetzner offsite.

```sh
set -a; . /run/agenix/pgbackrest.env; set +a
RDIR=/mnt/ultra/restore-test/pg; SOCK=/mnt/ultra/restore-test/sock
rm -rf "$RDIR" "$SOCK"; mkdir -p "$RDIR" "$SOCK"
chown postgres:postgres "$RDIR" "$SOCK"; chmod 700 "$RDIR"

# Lister les backups disponibles :
runuser -u postgres --whitelist-environment=PGBACKREST_REPO1_CIPHER_PASS,PGBACKREST_REPO2_CIPHER_PASS -- \
  pgbackrest --stanza=default info

# Restore du dernier backup (recovery jusqu'à cohérence, puis promotion) :
runuser -u postgres --whitelist-environment=PGBACKREST_REPO1_CIPHER_PASS,PGBACKREST_REPO2_CIPHER_PASS -- \
  pgbackrest --stanza=default --repo=2 restore --pg1-path="$RDIR" \
    --type=immediate --target-action=promote --archive-mode=off

printf "port = 5433\nunix_socket_directories = '%s'\n" "$SOCK" >> "$RDIR/postgresql.auto.conf"

sudo -u postgres env PGBACKREST_REPO1_CIPHER_PASS="$PGBACKREST_REPO1_CIPHER_PASS" \
  PGBACKREST_REPO2_CIPHER_PASS="$PGBACKREST_REPO2_CIPHER_PASS" \
  "$PG"/pg_ctl -D "$RDIR" -w -t 600 -l "$RDIR/startup.log" start

sudo -u postgres "$PG"/psql -h "$SOCK" -p 5433 -d vaultwarden -tAc 'select count(*) from users'

sudo -u postgres "$PG"/pg_ctl -D "$RDIR" stop
rm -rf /mnt/ultra/restore-test
```

**PITR (point-in-time)** : remplacer `--type=immediate` par
`--type=time --target='2026-07-01 12:00:00+02'` (rejeu des WAL jusqu'à cet instant).

**Restore réel sur l'instance live** (sinistre) : `systemctl stop postgresql`, restaurer
dans le vrai `PGDATA` (`/var/lib/postgresql/16`) avec `--pg1-path=/var/lib/postgresql/16`
**sans** `--archive-mode=off` ni override port/socket, puis `systemctl start postgresql`.

### 2b-bis. Restore Postgres depuis le dump offsite (désastre, dernier recours)

Quand pgBackRest n'est pas utilisable (passphrase perdue, repos corrompus…),
restaurer depuis le `pg_dumpall` logique offsite — il ne demande que restic + psql :

```sh
set -a; . /run/agenix/restic.env; set +a
REPO=sftp:u625917@u625917.your-storagebox.de:/home/restic/pg-dump
restic -r "$REPO" restore latest --target /mnt/ultra/restore-test
# Recharger le cluster complet (rôles + toutes les bases) :
sudo -u postgres "$PG"/psql -f /mnt/ultra/restore-test/mnt/ultra/pg-dump/pg-dumpall.sql
```

Le dump est fait avec `--clean --if-exists`, donc rejouable sur une instance vierge.

### 2c. Bare-metal / disaster recovery

1. Réinstaller NixOS, cloner le repo, restaurer les identités agenix master.
2. `nixos-rebuild switch --flake .#hyper` → reconstruit tout le système + secrets
   (les secrets rekeyed sont dans le repo ; la **clé SSH Hetzner est dans agenix**,
   donc l'offsite est joignable dès le premier boot — pas de chicken-and-egg).
3. Restaurer les données par ordre de priorité (§ ci-dessus) via 2a + 2b.
4. Zigbee : après restore de `database.db` + `coordinator_backup.json`, si le réseau ne
   se reforme pas, supprimer `coordinator_backup.json` et ré-appairer.
```
