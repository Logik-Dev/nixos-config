# Architecture de supervision (hôte hyper)

Stack complète : collecte → stockage → visualisation → alerting.

## Vue d'ensemble

```
exporters → Prometheus (9090) → Grafana (3002)
                                ↓
                        Alertmanager (9093) → ntfy (2586)
```

| Composant | Port | Module |
|---|---|---|
| Prometheus | 9090 | `monitoring/prometheus.nix` |
| Grafana | 3002 | `monitoring/grafana.nix` |
| Alertmanager | 9093 | `monitoring/alertmanager.nix` |
| alertmanager-ntty | 8000 | `monitoring/alertmanager.nix` (bridge webhook → ntfy) |
| ntfy | 2586 | `monitoring/notification.nix` |
| Loki | 3100 | `monitoring/loki.nix` |
| Alloy (logs→Loki) | — | `monitoring/alloy.nix` |
| Glance (dashboard) | 3004 | `monitoring/glance.nix` |

## Exporters Prometheus

Les ports sont référencés dynamiquement depuis la config des exporters
(`config.services.prometheus.exporters.*.port`), pas hardcodés.

| Exporter | Port | Module | Job name |
|---|---|---|---|
| node_exporter | 9100 | `monitoring/node.nix` | `node` |
| postgres_exporter | 9187 | `monitoring/postgres.nix` | `postgres` |
| nvidia-gpu exporter | 9835 | `monitoring/gpu.nix` | `nvidia-gpu` |
| blackbox_exporter | 9115 | `monitoring/blackbox.nix` | `blackbox_http` |
| restic exporters | 9760+ | `monitoring/restic.nix` | `restic` (un job par repo) |

### Blackbox

Scrape tous les services traefik (`config.traefik.services`) via HTTP 2xx.
Le relabel extrait le nom du service depuis l'URL pour les labels Prometheus.

## Alertes

7 alertes définies dans `monitoring/prometheus-alerts.nix` :

| Alerte | Condition | Sévérité | For |
|---|---|---|---|
| ServiceDown | `up == 0` | critical | 1m |
| HighDiskUsage | filesystem > 80% | warning | 5m |
| HighCpuLoad | load1 / cores > 4 | warning | 10m |
| HighMemoryPressure | MemAvailable / MemTotal < 0.10 | warning | 5m |
| ResticBackupStale | `time() - restic_backup_timestamp > 172800` | warning | 0m |
| ResticCheckFailed | `restic_check_success == 0` | critical | 5m |
| ResticExporterDown | `up{job="restic"} == 0` | warning | 30m |

## Notification (`notify.services`)

Le module `monitoring/notification.nix` expose l'option `notify.services`
(listOf str). Chaque service qui veut des notifications on-failure s'ajoute à
cette liste. Un template systemd `notify-failure@.service` envoie un message
ntfy quand l'unit échoue.

## Glance dashboard

`monitoring/glance.nix` auto-génère ses widgets monitor depuis
`config.traefik.services` filtré par `category`. Chaque service avec une
catégorie non-null devient un site entry. Voir [modules-pattern.md](modules-pattern.md)
pour le détail.