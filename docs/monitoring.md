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
| Loki | 3100 | `monitoring/loki.nix` |
| Alloy (logs→Loki) | — | `monitoring/alloy.nix` |
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
| restic exporters | 9760+ | `monitoring/restic.nix` | `restic` (un job par repo) |
| **traefik** (métriques natives) | 8083 | `networking/traefik/static.nix` | `traefik` |
| **authelia** (métriques natives) | 9959 | `security/authelia.nix` | `authelia` |
| **fail2ban exporter** | 9191 | `security/fail2ban.nix` | `fail2ban` |

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

- **Disponibilité** : `ServiceDown` (`up == 0`, hors `restic`), `ProbeFailure`,
  `PostgresDown`, `ResticExporterDown` (75m), `Fail2banExporterUnhealthy`.
- **Certificats / disques** : `TLSCertExpirySoon`, `HighDiskUsage`,
  `MountPointMissing` (/mnt/usb, /mnt/ultra), `FilesystemReadOnly`.
- **Charge / température** : `HighCpuLoad`, `HighMemoryPressure`,
  `TemperatureHigh`, `GpuTemperatureHigh`, `SystemdUnitFailed`.
- **Web / auth** : `TraefikHigh5xxRate`, `AutheliaAuthFailureSpike` (POST 401/403).
- **Postgres / PITR** : `PgWalArchiveStale`, `PgWalArchiveFailures`,
  `PgbackrestBackupStale`, `PgbackrestSpoolGrowing`, `PgbackrestMetricsMissing`.
- **Backups** : `ResticBackupStale` (max par repo), `ResticCheckFailed`,
  `ResticRepoEmpty`, `DrillStale` (dead-man des drills).

## Notification (`notify.services`)

`monitoring/notification.nix` expose l'option `notify.services` (listOf str).
Chaque service voulant une notif on-failure s'y ajoute ; un template
`notify-failure@.service` pousse les 30 dernières lignes de journal vers ntfy.
**Piège** : le module crée lui-même l'unité — un nom fautif donne une unité
fantôme jamais déclenchée (cf. audit P0-3/FAC-5).

Topics ntfy : `homelab-alerts` (Alertmanager), `service-failure` (notify),
`backup-verify` (drills). La route publique Traefik est **lecture seule**
(`GET/HEAD/OPTIONS`) ; seule la publication locale (`localhost:2586`) écrit.

## Glance dashboard

`monitoring/glance.nix` auto-génère ses widgets monitor depuis
`config.traefik.services` filtré par `category` : chaque service avec une
catégorie non-null devient un site entry. Voir [modules-pattern.md](modules-pattern.md).
