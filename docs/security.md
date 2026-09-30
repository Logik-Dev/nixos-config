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

## Routage inter-VLAN filtré (SEC-14) — corrigé

> **État : corrigé et déployé le 2026-09-29** (génération 507). La moitié ciblée
> est en place ; le chantier nftables reste ouvert (voir « Ce qui reste »).

**hyper était un routeur ouvert entre le VLAN IoT et le LAN.** Constaté et
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

### Le correctif déployé

`modules/hosts/hyper/inter-vlan-firewall.nix` — une chaîne `iot-forward`
appendue à FORWAD pour tout ce qui entre par `br-iot` :

| # | Règle | Rôle |
|---|---|---|
| 1 | `ESTABLISHED,RELATED → ACCEPT` | les réponses aux flux ouverts depuis le côté de confiance passent : LAN → IoT et hôte → IoT continuent de fonctionner |
| 2 | `-d 192.168.10.0/24 → DROP` | le trou d'origine |
| 3 | `-d 10.88.0.0/16 → DROP` | réseau podman (immich) |
| 4 | `-d 10.200.0.0/30 → DROP` | veth du namespace `vpn` |
| 5 | `RETURN` | le reste retombe sur la politique FORWARD : on ferme le mouvement latéral, **pas** l'egress |

La chaîne est reconstruite à chaque démarrage du pare-feu (`-N` / `-F`, puis
`-C` avant `-A` pour le jump) : l'unité ne vidant pas FORWARD, une simple
insertion empilerait un jeu de doublons à chaque `nh os switch`. Vérifié : après
un `test` puis un `switch`, le jump n'apparaît **qu'une fois**.

**Vérification par sonde** (namespace jetable sur `br-iot`, passerelle
192.168.21.241, supprimé après chaque essai) — chaque ligne confirmée par le
compteur de la règle correspondante :

| Depuis le VLAN IoT vers | Avant | Après |
|---|---|---|
| 192.168.10.1 (LAN) | ping + TCP/443 OK | **bloqué** |
| 10.88.0.2 (conteneur immich-ml) | — | **bloqué** |
| 10.200.0.2 (WebUI dans le netns vpn) | — | **bloqué** |
| 192.168.21.241:1883 (mosquitto) | OK | **OK** — c'est de l'INPUT, HA n'est pas impacté |
| 192.168.21.181:8123 (VM HA) | OK | **OK** — trafic bridgé, hors FORWARD |

Non-régression au même moment : 0 unité en échec, `hass.hyper.logikdev.fr` → 200
via Traefik, netns `vpn` toujours sur son tunnel (IP de sortie AirVPN).

### Ce qui reste

- **IoT → tailnet n'est pas couvert.** Le jump est appendu, donc `ts-forward`
  passe avant et accepte tout ce qui sort par `tailscale0`. Ce chemin est
  gouverné par les ACL Tailscale ([tailscale-acl.md](tailscale-acl.md), SEC-11),
  pas par le pare-feu de l'hôte. Ne pas « corriger » en insérant le jump en
  position 1 : netavark et tailscale réinsèrent les leurs en tête au
  redémarrage, l'ordre ne tiendrait pas.
- **IPv4 seulement**, volontairement : hyper n'a aucune adresse IPv6 routable ni
  aucune route IPv6 hors `tailscale0`, donc il n'existe pas de chemin v6 entre
  les deux segments. Si l'IPv6 est un jour activé sur ces VLAN, il faut le
  jumeau `ip6tables`.
- **Le chantier structurel** reste entier : `networking.nftables.enable` +
  `networking.firewall.filterForward` + `extraForwardRules`. ⚠️ Passer le FORWARD
  en *drop* casserait le **subnet routing Tailscale**, **netavark** et la **veth
  du namespace `vpn`** tant que les règles ne sont pas écrites.

## Home Assistant exposé au WAN — anti-bourrage activé (SEC-19, corrigé)

**Constaté le 2026-09-29.** `ha.hyper.logikdev.fr` résout **publiquement**
(CNAME vers `logikdev.fr` → l'IP WAN, vérifié contre `1.1.1.1`), et les ports
80/443 sont redirigés par le routeur. La page de connexion de Home Assistant est
donc joignable depuis Internet.

| Couche | État |
|---|---|
| Authelia | **absente** — choix assumé, les clients natifs ne suivent pas un forwardAuth |
| Rate-limit Traefik | 150 req/s en moyenne, burst 300 — très large pour du bourrage d'identifiants |
| Bannissement HA après échecs | **activé le 2026-09-30** : `login_attempts_threshold = 5`, vérifié promu |

`ip_ban_enabled` est pourtant à `true` : c'est le seuil à `-1`
(`NO_LOGIN_ATTEMPT_THRESHOLD`, le défaut de HA) qui neutralise le mécanisme.

### Le correctif, et pourquoi il est sûr ici

Régler `login_attempts_threshold` à une valeur positive (5 est un choix
raisonnable). HA bannit alors l'IP fautive après N échecs.

Ce qui rend ce bannissement **utile plutôt que dangereux**, c'est que la
configuration de proxy est correcte : `use_x_forwarded_for = true` et
`trusted_proxies = ['127.0.0.1/32']`. HA lit donc la **vraie IP du client** dans
`X-Forwarded-For` et bannit l'attaquant. Sans cela il bannirait `127.0.0.1`,
c'est-à-dire Traefik — et mettrait tout le monde dehors d'un coup.

⚠️ **À faire dans l'UI, pas en nix** : `.storage/http` est géré par l'interface
depuis HA 2026.8, et l'YAML n'en est qu'une migration one-shot qu'une promotion
ratée écarte définitivement. Voir `docs/home-assistant-nix-plan.md` §9.

### Pistes plus fortes, non retenues pour l'instant

- Restreindre la route `ha` au LAN et au tailnet, et passer par Tailscale depuis
  l'extérieur. Écarté pour l'instant parce que ça change l'usage du téléphone
  hors du domicile — à arbitrer.
- Mettre HA derrière Authelia : incompatible avec l'application compagnon, qui
  ne suit pas la redirection du forwardAuth.

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
- ~~**SEC-19**~~ : **corrigé le 2026-09-30** — `login_attempts_threshold = 5`.
  HA reste joignable depuis Internet sans Authelia (choix assumé, clients
  natifs), mais le bannissement après échecs protège désormais la page de
  connexion. C'était la condition posée avant d'ouvrir 8123 sur le VLAN IoT.
- **SEC-14** : **corrigé le 2026-09-29** (moitié ciblée déployée, génération
  507). Restent ouverts : le chemin IoT → tailnet (relève des ACL Tailscale,
  SEC-11) et le chantier nftables/`filterForward`.
