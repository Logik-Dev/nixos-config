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

## Routage inter-VLAN non filtré (SEC-14)

**hyper est un routeur ouvert entre le VLAN IoT et le LAN.** Constaté et
**vérifié empiriquement le 2026-09-29**, indépendamment de tout projet en cours.

Trois conditions se cumulent :

| Condition | État mesuré | Origine |
|---|---|---|
| Transfert IP activé | `net.ipv4.ip_forward = 1` | posé par Tailscale (subnet router) |
| Chaîne FORWARD sans filtre | `policy ACCEPT`, aucune règle NixOS | `networking.firewall` ne filtre **que** l'INPUT |
| Pattes sur les deux réseaux | `management` 192.168.10.100, `br-iot` 192.168.21.241 | `hosts/hyper/ifnames.nix` |

`networking.firewall.filterForward` n'est pas activable en l'état : l'option est
**nftables uniquement**, et hyper tourne en mode iptables (`nftables.service`
inactif, `iptables v1.8.13 (nf_tables)` = shim de compatibilité). Le `rp_filter`
est en mode *loose* (`2`) sur les deux interfaces, donc il ne bloque rien ici.

**Conséquence** : un objet compromis sur vlan21 qui prend `192.168.21.241` comme
passerelle atteint `192.168.10.0/24` **en contournant les règles inter-VLAN de
l'UniFi** — celles-ci ne voient jamais le trafic, qui ne passe pas par le routeur.

Vérification faite (namespace jetable attaché à `br-iot`, 192.168.21.250/24,
route par défaut via 192.168.21.241, supprimé aussitôt) : ping **et** TCP/443
vers 192.168.10.1 aboutissent. Ce n'est pas théorique.

À cela s'ajoute que Tailscale annonce **les deux** `/24`
(`--advertise-routes=192.168.10.0/24,192.168.21.0/24`) : la portée dépend alors
des ACL Tailscale (`docs/tailscale-acl.md`), pas du pare-feu de l'hôte.

Deux autres constats du même audit :

- **`br_netfilter` n'est pas chargé** : le trafic *bridgé* sur `br-iot` (donc
  vers la VM Home Assistant, `vnet0`) ne traverse aucune règle iptables. Le port
  8123 de HA est joignable sans filtre depuis n'importe quel objet de vlan21.
- Ce n'est **pas** un argument pour sortir Home Assistant du VLAN IoT : HA doit
  par fonction parler au segment non fiable (voir
  `docs/home-assistant-nix-plan.md` §3.2).

### Pistes de correction

1. **Ciblé, à faible risque** — une règle FORWARD `br-iot → management : drop`
   (avec `ct state established,related accept` pour ne pas casser les réponses
   aux flux sortants du LAN). Ne touche ni Tailscale, ni podman, ni la veth VPN.
2. **Structurel** — `networking.nftables.enable = true` +
   `networking.firewall.filterForward = true`, avec des
   `extraForwardRules` explicites. ⚠️ Passer le FORWARD en *drop* casserait le
   **subnet routing Tailscale**, **netavark** (conteneurs immich) et la **veth
   du namespace `vpn`** tant que les règles ne sont pas écrites. Ce n'est pas une
   ligne : c'est un chantier à part entière, à valider en
   `nixos-rebuild test` avant de persister.

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
  Note : la migration de Home Assistant en natif rendrait le listener `br-iot`
  **fermable** (HA passerait en loopback), ce qui retire l'essentiel du sujet —
  voir `docs/home-assistant-nix-plan.md` §3.2 d.
- **SEC-11** : appliquer le JSON d'ACL Tailscale dans la console.
- **SEC-14** : routage inter-VLAN non filtré sur hyper (section ci-dessus) —
  vérifié le 2026-09-29, non corrigé.
