# Restore drill — vérification & restauration des backups

Ce document couvre (1) les vérifications **automatiques** hebdomadaires et (2) les
procédures **manuelles** de restauration. Objectif : prouver que les backups sont
réellement restaurables, pas seulement qu'ils tournent.

Architecture backup : chaque source restic est sauvegardée vers plusieurs cibles
(`s3`/rustfs, `usb`, `hetzner` offsite, parfois `local`). Postgres est sauvegardé
à part par **barman** (base backup hebdo + archivage WAL continu) vers
`s3://pg-backups/pg-16` (rustfs).

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
| `restic-check` | dim. 05:00 | `restic check` structurel sur **tous** les repos + `--read-data` (blobs réels) sur tout sauf `immich`/`rustfs` (trop gros, différé) |
| `restore-canary` | dim. 06:00 | Restore réel de **Zigbee depuis Hetzner** (offsite) → `PRAGMA integrity_check` |
| `postgres-restore-drill` | dim. 07:00 | Restore barman réel → instance jetable → requêtes sur vaultwarden/prowlarr |

Lancer un drill à la main :

```sh
systemctl start postgres-restore-drill.service
journalctl -u postgres-restore-drill.service -f
```

> **Différé** : le `--read-data` complet sur `immich` (~440 Go) et `rustfs` (~485 Go,
> il contient les repos s3 dont immich-s3) est volontairement exclu (voir `bigSources`
> dans le module). À réactiver plus tard, une fois le seed offsite d'Immich terminé.

---

## 2. Procédures manuelles

Les binaires ne sont pas dans le PATH système (chemins nix store). Récupérer les
chemins courants :

```sh
BARMAN=$(dirname "$(systemctl cat postgresql-base-backup.service \
  | grep -o '/nix/store/[^ ]*barman[^ ]*/bin/barman-cloud-backup' | head -1)")
PG=$(dirname "$(readlink -f "$(systemctl show postgresql.service -p ExecStart --value \
  | grep -o '/nix/store/[^ ]*/bin/postgres' | head -1)")")
```

`restic` est dans le PATH système. Les creds sont dans agenix (`root` uniquement) :
`/run/agenix/restic.env` (restic + S3) et `/run/agenix/s3.env` (barman).

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

### 2b. Restore Postgres (barman → instance jetable, non destructif)

Procédure validée par `postgres-restore-drill`. Restaure vers un `PGDATA` scratch et
démarre une instance **isolée** (port 5433, socket dédiée, archivage coupé) — ne touche
jamais l'instance live.

```sh
set -a; . /run/agenix/s3.env; set +a
EP=http://localhost:9000; S3=s3://pg-backups; SRV=pg-16
RDIR=/mnt/ultra/restore-test/pg; SOCK=/mnt/ultra/restore-test/sock
rm -rf "$RDIR" "$SOCK"; mkdir -p "$RDIR" "$SOCK"

# Dernier base backup (ou choisir un ID précis dans la liste) :
"$BARMAN"/barman-cloud-backup-list --cloud-provider aws-s3 --endpoint-url "$EP" "$S3" "$SRV"
BID=$("$BARMAN"/barman-cloud-backup-list --cloud-provider aws-s3 --endpoint-url "$EP" "$S3" "$SRV" | tail -1 | awk '{print $1}')

"$BARMAN"/barman-cloud-restore --cloud-provider aws-s3 --endpoint-url "$EP" "$S3" "$SRV" "$BID" "$RDIR"

cat >> "$RDIR/postgresql.auto.conf" <<CONF
restore_command = '$BARMAN/barman-cloud-wal-restore --cloud-provider aws-s3 --endpoint-url $EP $S3 $SRV %f %p'
recovery_target = 'immediate'
recovery_target_action = 'promote'
archive_mode = off
hot_standby = on
port = 5433
unix_socket_directories = '$SOCK'
CONF
touch "$RDIR/recovery.signal"; chown -R postgres:postgres /mnt/ultra/restore-test; chmod 700 "$RDIR"

sudo -u postgres env AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
  "$PG"/pg_ctl -D "$RDIR" -w -t 600 -l "$RDIR/startup.log" start

sudo -u postgres "$PG"/psql -h "$SOCK" -p 5433 -d vaultwarden -tAc 'select count(*) from users'

sudo -u postgres "$PG"/pg_ctl -D "$RDIR" stop
rm -rf /mnt/ultra/restore-test
```

**PITR (point-in-time)** : pour rejouer au-delà de la cohérence minimale, remplacer
`recovery_target = 'immediate'` par `recovery_target_time = '2026-07-01 12:00:00'`.

**Restore réel sur l'instance live** (sinistre) : `systemctl stop postgresql`, restaurer
dans le vrai `PGDATA` (`/var/lib/postgresql/16`), **garder** `archive_mode` et enlever le
`port`/`socket` override, puis `systemctl start postgresql`.

### 2c. Bare-metal / disaster recovery

1. Réinstaller NixOS, cloner le repo, restaurer les identités agenix master.
2. `nixos-rebuild switch --flake .#hyper` → reconstruit tout le système + secrets
   (les secrets rekeyed sont dans le repo ; la **clé SSH Hetzner est dans agenix**,
   donc l'offsite est joignable dès le premier boot — pas de chicken-and-egg).
3. Restaurer les données par ordre de priorité (§ ci-dessus) via 2a + 2b.
4. Zigbee : après restore de `database.db` + `coordinator_backup.json`, si le réseau ne
   se reforme pas, supprimer `coordinator_backup.json` et ré-appairer.
```
