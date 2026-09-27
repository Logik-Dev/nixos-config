# Homelab NixOS

Fully automated NixOS configuration for my homelab, built with `flake-parts` + `import-tree` using a dendritic module pattern.

## Hosts

| Host | Arch | Role |
|---|---|---|
| `hyper` | x86_64-linux | Production server |
| `sonicmaster` | x86_64-linux | Media server (offline) |
| `m4` | aarch64-darwin | Laptop |

## Deploy

Il n'y a pas de flake app par hôte ; on utilise `nh` (ou `darwin-rebuild` pour m4).

```bash
# hyper : depuis m4, build + activation à distance
nh os switch --hostname hyper --target-host logikdev@hyper --build-host logikdev@hyper

# m4 (darwin) : en local
sudo darwin-rebuild switch --flake .#m4

# sonicmaster : en local (sshd désactivé → pas de déploiement distant)
nh os switch --hostname sonicmaster
```

Validation :

```bash
nix flake check                      # treefmt + checks d'éval des hôtes du système courant
nix flake check --all-systems --no-build   # éval de tous les hôtes (sans build)
nix fmt                              # nixfmt + deadnix + statix
```

## Secrets

Managed via [agenix](https://github.com/ryantm/agenix) + [agenix-rekey](https://github.com/oddlama/agenix-rekey) with Yubikey as primary identity.

Encrypted `.age` files in `secrets/hosts/<hostname>/`. To add a new secret:

```bash
# depuis le devshell (nix develop), chiffre et écrit le fichier :
agenix -e secrets/hosts/<hostname>/<name>.age
# puis référence-le : config.age.secrets."<name>".path
nix run .#agenix-rekey               # recalcule secrets/rekeyed/
```

Rekeyed outputs committed to `secrets/rekeyed/` for target hosts.
`cp <plaintext> …/<name>.age` ne chiffre **rien** — ne pas faire ça.

## Modules

Feature modules live under `modules/features/<category>/<name>.nix`, host config under `modules/hosts/<hostname>/`. La plupart des modules **assignent directement** `flake.modules.<classe>.<nom> = { … }` (les autres déclarent `.imports` pour composer) ; auto-découverte par `import-tree`, aucun `default.nix` à maintenir. Détails : [docs/modules-pattern.md](docs/modules-pattern.md).

## Documentation

| Doc | Contenu |
|---|---|
| [docs/audit-2026-09.md](docs/audit-2026-09.md) | Audit complet + feuille de route (IDs P0/SEC/MON/BAK/CLN/FAC/ADD/DOC) |
| [docs/security.md](docs/security.md) | Authelia, surface réseau, sudo, secrets, MQTT/ntfy, chiffrement |
| [docs/networking.md](docs/networking.md) | Traefik, AdGuard, Tailscale, VPN, MQTT, UniFi, DDNS, ports |
| [docs/backups.md](docs/backups.md) | Stratégie restic/pgBackRest, sources sauvegardées ou non |
| [docs/restore-drill.md](docs/restore-drill.md) | Vérifications auto + procédures de restauration |
| [docs/monitoring.md](docs/monitoring.md) | Prometheus/Grafana/Alertmanager, exporters, alertes |
| [docs/services.md](docs/services.md) | Stack applicative : services, URLs, dépendances, GPU |
| [docs/torrent-vpn.md](docs/torrent-vpn.md) | Stack torrent qBittorrent + AirVPN |
| [docs/music-home.md](docs/music-home.md) | Musique/voix (Spotify Family, Alexa, Sonos, Music Assistant) |
| [docs/tailscale-acl.md](docs/tailscale-acl.md) | ACL Tailscale (JSON + procédure) |
| [docs/modules-pattern.md](docs/modules-pattern.md) | Pattern dendritic, factories |
| [docs/add-host.md](docs/add-host.md) | Ajouter un hôte (facter, hostKeys, secrets) |

## VCS

[Jujutsu](https://github.com/jj-vcs/jj) (`jj`) — the `.jj/` directory is managed by jj alongside `.git/`.
