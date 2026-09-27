# Stack applicative (hôte hyper)

Inventaire des services applicatifs : URL publique, port interne, authentification
et dépendances. Les ports sont ceux de `config.traefik.services` (backend loopback
par défaut). URL = `https://<nom>.hyper.logikdev.fr`.

## Services exposés (via Traefik)

| Service | Port | Catégorie Glance | Authelia | Dépendances / notes |
|---|---|---|---|---|
| `jellyfin` | 8096 | Médias | **non** (clients TV/apps) | GPU (VAAPI) |
| `immich` | 2283 | Médias | **non** (apps natives) | Postgres, Redis, containeur `immich-ml` (GPU) |
| `seerr` | 5055 | Médias | oui | SQLite (`/var/lib/private/jellyseerr`) |
| `radarr` | 7878 | Médias | oui | Postgres (main+logs), `/mnt/ultra` |
| `sonarr` | 8989 | Médias | oui | Postgres (main+logs), `/mnt/ultra` |
| `prowlarr` | 9696 | Médias | oui | Postgres, derrière AirVPN (indexers) ; dataDir défaut `/var/lib/private/prowlarr` (DynamicUser) |
| `sabnzbd` | 8088 | Médias | oui | `/mnt/storage/medias` |
| `qbittorrent` | 8090 | Médias | oui | AirVPN (kill-switch), `/mnt/storage/medias` |
| `audiobookshelf` | 13378 | Médias | **non** (apps natives) | `/var/lib/audiobookshelf` (DB/meta), bibliothèques `/mnt/storage/medias/{books,audiobooks}` |
| `bindery` | 8787 | Médias | oui | **containeur podman** (`--network=host`, UID 1000:991) ; Prowlarr/qBittorrent/SABnzbd ; config `/mnt/ultra/bindery`, **mount unique** `/mnt/storage/medias` (hardlinks downloads→bibliothèques, chemins identiques à l'hôte → pas de remap) |
| `rankoder` | 8765 | Médias | oui | MQTT, GPU, `/mnt/storage/medias/rankoder` |
| `hass` | 8123 | Maison | **non** (auth propre) | **VM libvirt** `192.168.21.181` (bridge `br-iot`) |
| `mealie` | 9999 | Maison | oui | Postgres, `/var/lib/private/mealie` |
| `paperless` | 28981 | Maison | oui (SSO `Remote-User`) | Postgres, Gotenberg, Tika, `/mnt/local` |
| `vaultwarden` | 8082 | Maison | **non** (clients Bitwarden) | Postgres |
| `zigbee` | 8788 | Maison | oui | MQTT, dongle `/dev/ttyUSB0` |
| `grafana` | 3002 | Supervision | oui | Prometheus, Loki |
| `ntfy` | 2586 | Supervision | **non** (auth ntfy ; public en lecture seule) | Secrets `ntfy-reader-pw` |
| `dns` | 3000 | Réseau & Stockage | oui | AdGuard Home (DNS de l'hôte) |
| `unifi` | 8443 | Réseau & Stockage | oui | HTTPS self-signed, MongoDB-ce |
| `syncthing` | 8384 | Réseau & Stockage | oui | Sync `paperless-consume` (m4↔hyper) |
| `n8n` | 5678 | Automatisation | oui | Postgres (`n8n`), Ollama |

Hors glossaire (non catégorisés) : `auth` (portail Authelia 9091) et `home`
(Glance 3004) — exclus du dashboard.

Stack livres : **Bindery** (containeur podman ; acquisition/renommage via Prowlarr +
qBittorrent/SABnzbd existants) dépose ses imports dans
`/mnt/storage/medias/{books,audiobooks}`, servis par **Audiobookshelf** (audiobooks +
podcasts + ebooks). Bindery ne passe pas par le VPN (Prowlarr porte le trafic
indexeurs) ; `BINDERY_DOWNLOAD_ALLOW_LOOPBACK=1` est requis car Prowlarr est sur
loopback. Remplace **Readarr** (projet archivé le 2025-06-27, backend métadonnées mort).

## Exceptions Authelia

Volontairement sans forwardAuth (clients natifs ne gèrent pas une redirection) :
**Audiobookshelf, Immich, Jellyfin, Vaultwarden, Home Assistant, ntfy**. Chacun a sa
propre auth (app, API token ou mot de passe). Traefik `stripAuthHeaders` empêche toute
usurpation de `Remote-User`. Détails : [security.md](security.md).

## Dépendances internes

- **Postgres 16** : authelia, immich, n8n, paperless, mealie, vaultwarden,
  prowlarr/radarr/sonarr (bases `-main`/`-logs`, ownership via hook
  `seedbox-db-ownership`). PITR pgBackRest + dump logique.
- **Redis** : cache Immich (`services.redis.servers.immich`).
- **Mosquitto (MQTT)** : zigbee2mqtt, rankoder, Home Assistant (VM).
- **Gotenberg + Tika** : conversion/OCR Paperless (Gotenberg déplacé sur 3001,
  conflit port 3000 avec AdGuard).
- **Ollama** (P4000) : tri de mails n8n ; `ollama` sur m4 = booster batch.

## GPU P4000 (8 Go) partagé

Accélération partagée entre : `immich-ml` (CUDA), `ollama-cuda`, `jellyfin`
(nvidia-vaapi), `rankoder` (hardwareAcceleration). Contraintes :

- un seul modèle Ollama chargé à la fois (`OLLAMA_MAX_LOADED_MODELS=1`,
  `OLLAMA_KEEP_ALIVE=5m`) pour rendre la VRAM à immich-ml ;
- la P4000 est Pascal (sm_61) : Ollama est épinglé sur `cudaCapabilities = ["6.1"]`.

## Contraintes `/mnt/ultra`

- Monté `nofail` ; les jobs/services qui en dépendent utilisent
  `RequiresMountsFor` (sinon écriture silencieuse sur le disque racine).
- Appartient à `logikdev:media` (tmpfiles) ; les services média tournent en
  `group = "media"` (UMask 0002).
- **Paperless est volontairement sur `/mnt/local`** (et non `/mnt/ultra`) :
  systemd-tmpfiles refuse de créer des sous-dossiers via une « unsafe path
  transition » sous un parent non-root.
- Les exclusions de backup (cache/thumbs/transcodes) et le détail 3-2-1 :
  [backups.md](backups.md).
