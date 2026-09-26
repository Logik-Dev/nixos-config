# Sécurité du homelab

Document de référence (audit 2026-09, DOC-8). Décrit le modèle d'authentification,
la surface réseau réelle, la gestion des secrets et les risques assumés.

## Authentification web (Authelia)

Authelia tourne sur **hyper** (`modules/features/security/authelia.nix`), protège
tous les vhosts `*.logikdev.fr` via le forwardAuth Traefik, et s'appuie sur
postgres (`authelia-main`).

Politique (`access_control`, évaluée dans l'ordre) :

| Source | Politique | Effet |
|---|---|---|
| `192.168.10.0/24` (LAN) et `100.64.0.0/10` (tailnet) | `one_factor` | login Authelia, **sans 2FA** |
| tout le reste (WAN) | `two_factor` | login + 2FA |
| défaut | `deny` | tout ce qui n'est pas listé |

- L'ancien `bypass` total sur le LAN (et une IP Tailscale de m4 codée en dur) a
  été remplacé par `one_factor` + le CIDR tailnet : plus d'IP par appareil à
  maintenir, et plus d'accès silencieux sans session.
- L'IP Tailscale de m4 (`100.76.159.66`) n'est plus dupliquée : elle vit dans
  `constants.hosts.m4.tailscaleIp` (utilisée par ollama pour son bind).
- `stripAuthHeaders` supprime tout header `Remote-*` entrant avant le
  forwardAuth : seul Authelia peut poser `Remote-User` (SSO Paperless).

### Services hors Authelia (auth applicative)

Volontairement **pas** derrière Authelia, car leurs clients natifs ne peuvent pas
suivre une redirection forward-auth :

- **Immich** (`medias/immich.nix`) — apps mobile/desktop, bind loopback.
- **Jellyfin** (`medias/jellyfin.nix`) — clients TV/apps.
- **Vaultwarden** (`security/vaultwarden.nix`) — clients Bitwarden ; `SIGNUPS_ALLOWED=false`.
- **Home Assistant** (`hosts/hyper/libvirt.nix`, VM `192.168.21.181`) — auth propre.

Les \*arr (prowlarr/radarr/sonarr/sabnzbd) restent bien derrière Authelia, en
`one_factor` depuis le LAN/tailnet.

## Surface réseau (hyper)

Ports ouverts dans le firewall NixOS (`networking.firewall.allowedTCPPorts`) :

| Port | Service | Portée |
|---|---|---|
| 22 | sshd | **clé uniquement** (`PasswordAuthentication=false`, `KbdInteractiveAuthentication=false`), fail2ban |
| 53 | AdGuard Home | LAN + tailnet (résolveur DNS) |
| 80 / 443 | Traefik | LAN ; exposition WAN = redirection routeur (ACME Cloudflare DNS-01) |
| 8080 | UniFi (informat) | LAN/IoT |
| 22000 | Syncthing | LAN/tailnet |
| 1883 | Mosquitto MQTT | **uniquement `br-iot`** (loopback toujours autorisé) + port forward AirVPN (wg0) |

- SSH n'est pas redirigé vers le WAN (seul le tailnet/LAN y accède) ; `--ssh`
  Tailscale a été retiré (voir `docs/tailscale-acl.md`).
- `fail2ban` (`security/fail2ban.nix`) bannit les scans SSH (ignore LAN + tailnet).

## Modèle sudo (hyper)

`security.sudo.wheelNeedsPassword = false` (`security/hardening.nix`) : les
déploiements distants (`nh os switch`) enchaînent des `sudo` internes, un mot de
passe casserait la non-interactivité. Sur un serveur mono-admin headless, la clé
SSH est de toute façon root-équivalente. `pam.sshAgentAuth` est activé.

**U2F/WebAuthn n'est pas utilisé sur hyper** : la YubiKey devrait être branchée
sur le serveur (inutilisable pour une session SSH distante), et le parc Mac est
USB-C. Décision assumée, compensée par SSH clé-only + fail2ban.

## Secrets

- **agenix** + agenix-rekey (`storageMode = "local"`), secrets `.age` dans
  `secrets/hosts/<host>/`, auto-découverts par `security/secrets.nix`.
- Master identity : YubiKey + `~/.config/age/keys.txt` de secours.
- Au runtime, les secrets sont montés dans `/run/agenix/<nom>`.
- **Rotation** : copie dans Vaultwarden (restic/pgBackRest), `age` identité sur
  YubiKey. Un `.conf` AirVPN contient la clé privée → ne jamais le committer.
- `users.mutableUsers = false` : tout compte non déclaré est supprimé à
  l'activation suivante.

## MQTT & ntfy

- **MQTT** (mosquitto) : sans TLS, un mot de passe partagé, listener limité au
  bridge IoT. Durcissement prévu (comptes distincts + ACL + TLS) = **SEC-3b**.
- **ntfy** : la route publique est **lecture seule** (GET/HEAD/OPTIONS via une
  option `traefik.services.ntfy.methods`) ; les publishers (`notify-failure`,
  smartd, drills) postent en `localhost:2586`, hors Traefik. Les alertes ne
  peuvent donc plus être écrites depuis Internet.

## ACL Tailscale

Hors dépôt (console Tailscale) : voir `docs/tailscale-acl.md` (JSON versionné +
procédure). hyper est **subnet router** (`--advertise-routes=192.168.10.0/24,192.168.21.0/24`),
sans `--ssh`.

## Chiffrement disque (SEC-12) — risque accepté

hyper **n'a aucun chiffrement disque** (ext4/xfs/btrfs sur LVM). Le disque
système contient postgres (Vaultwarden, \*arr) et les WAL en clair.

Risque assumé : serveur headless, déverrouillage distant complexe à opérer.
Compensations :

- sauvegardes **offsite chiffrées** (restic `sftp` + pgBackRest repo2, passphrases
  agenix) ;
- master key agenix sur YubiKey (pas sur le disque) ;
- accès physique maîtrisé (domicile).

Piste future : réinstall avec **LUKS + TPM2 (systemd-cryptenroll/clevis)** pour
un déverrouillage automatique au boot sans intervention.

## Restes ouverts (audit 2026-09)

- **SEC-3b** : comptes MQTT distincts + ACL minimales + TLS 8883 (HA à mettre à jour).
- **SEC-11** : appliquer le JSON d'ACL Tailscale dans la console.
