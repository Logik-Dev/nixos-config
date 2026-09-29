# Architecture de supervision (hôte hyper)

Stack complète : collecte → stockage → visualisation → alerting.

## Vue d'ensemble

```
exporters → Prometheus (9090) → Grafana (3002)
                                ↓
                        Alertmanager (9093) → alertmanager-ntfy (8000, /hook) → ntfy (2586)
```

| Composant | Port | Module |
|---|---|---|
| Prometheus | 9090 | `monitoring/prometheus.nix` |
| Grafana | 3002 | `monitoring/grafana.nix` |
| Alertmanager | 9093 | `monitoring/alertmanager.nix` |
| alertmanager-ntfy | 8000 | `monitoring/alertmanager.nix` (bridge webhook → ntfy, **`POST /hook`**) |
| ntfy | 2586 | `monitoring/notification.nix` |
| Glance (dashboard) | 3004 | `monitoring/glance.nix` |

## Exporters Prometheus

Les ports des exporters nixpkgs sont référencés dynamiquement
(`config.services.prometheus.exporters.*.port`).

| Exporter | Port | Module | Job name |
|---|---|---|---|
| node_exporter | 9100 | `monitoring/node.nix` | `node` |
| postgres_exporter | 9187 | `monitoring/postgres.nix` | `postgres` |
| nvidia-gpu exporter | 9835 | `monitoring/gpu.nix` | `nvidia-gpu` |
| blackbox_exporter | 9115 | `monitoring/blackbox.nix` | `blackbox_http` |
| **traefik** (métriques natives) | 8083 | `networking/traefik/static.nix` | `traefik` |
| **authelia** (métriques natives) | 9959 | `security/authelia.nix` | `authelia` |
| **fail2ban exporter** | 9191 | `security/fail2ban.nix` | `fail2ban` |

Les métriques restic ne sont **pas** produites par un exporter : chaque unité de
backup *pousse* ses métriques dans le textfile de node_exporter
(`monitoring/lib/_restic-metrics.nix`). L'ancien `prometheus-restic-exporter`
(un process par repo, 56 au total, en sftp) a été supprimé le 2026-09-27.

### Blackbox

Scrape tous les services traefik (`config.traefik.services`) via le module
`http_2xx`. Attention : `valid_status_codes = [200, 301, 302, 401, 403]` et
`follow_redirects = true` — 401/403 comptent comme « up » (apps à auth propre :
Immich, Jellyfin, Vaultwarden) et, pour les services derrière Authelia, le probe
suit la redirection et valide le portail, **pas** le backend (couvert par les
`check-url` directs de Glance). Le relabel extrait le nom du service depuis l'URL.

## Alertes

26 règles (25 noms) dans `monitoring/prometheus-alerts.nix`, toutes groupées dans
Alertmanager → ntfy :

- **Disponibilité** : `ServiceDown` (`up == 0`), `ProbeFailure`,
  `PostgresDown`, `Fail2banExporterUnhealthy`.
- **Certificats / disques** : `TLSCertExpirySoon`, `HighDiskUsage`,
  `MountPointMissing` (/mnt/usb, /mnt/ultra), `FilesystemReadOnly`.
- **Charge / température** : `HighCpuLoad`, `HighMemoryPressure`,
  `TemperatureHigh`, `GpuTemperatureHigh`, `SystemdUnitFailed`.
- **Web / auth** : `TraefikHigh5xxRate`, `AutheliaAuthFailureSpike` (POST 401/403).
- **Postgres / PITR** : `PgWalArchiveStale`, `PgWalArchiveFailures`,
  `PgbackrestBackupStale`, `PgbackrestSpoolGrowing`, `PgbackrestMetricsMissing`.
- **Backups** : `ResticBackupStale` (max par repo), `ResticCheckFailed`,
  `ResticRepoEmpty`, `ResticMetricsMissing` (dead-man des métriques push), `DrillStale` (dead-man des drills).

## Notification (`notify.services`)

`monitoring/notification.nix` expose l'option `notify.services` (listOf str).
Chaque service voulant une notif on-failure s'y ajoute ; un template
`notify-failure@.service` pousse les 30 dernières lignes de journal vers ntfy.
**Piège** : le module crée lui-même l'unité — un nom fautif donne une unité
fantôme jamais déclenchée (cf. audit P0-3/FAC-5).

Topics ntfy : `homelab-alerts` (Alertmanager), `service-failure` (notify),
`backup-verify` (drills). La route publique Traefik est **lecture seule**
(`GET/HEAD/OPTIONS`) ; seule la publication locale (`localhost:2586`) écrit.

**Publication garantie** : `push_ntfy` (`monitoring/lib/_ntfy.nix`) réessaie
~28 s puis **met en attente dans `/var/lib/ntfy-spool`** (drop-box `1733` : les
publieurs non-root, comme le drill postgres, y déposent sans pouvoir lister).
`ntfy-spool-drain.timer` (2 min) rejoue les messages et expose
`ntfy_spool_pending` / `ntfy_spool_oldest_age_seconds` /
`ntfy_spool_drain_timestamp_seconds` → alertes `NtfySpoolStuck` et
`NtfySpoolDrainMissing`. Motif : un `curl` sans reprise perdait des alertes en
silence au boot (ntfy-sh écoute après les premières unités en échec) — cf.
[notifications-plan.md](notifications-plan.md) §2.1.

Le `--collector.systemd.unit-include` de node_exporter (`monitoring/node.nix`)
est construit par **union** de motifs larges et de `config.notify.services` :
la liste écrite à la main avait dérivé et laissait 15 unités notifiées hors de
portée de `SystemdUnitFailed` (§2.4 du même plan).

## Glance dashboard

`monitoring/glance.nix` auto-génère ses widgets monitor depuis
`config.traefik.services` filtré par `category` : chaque service avec une
catégorie non-null devient un site entry. Voir [modules-pattern.md](modules-pattern.md).
