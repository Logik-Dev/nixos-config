# Architecture réseau (hôte hyper)

Vue d'ensemble des briques réseau/sécurité de hyper. Détail de l'authentification
et des risques : [security.md](security.md) ; ACL Tailscale : [tailscale-acl.md](tailscale-acl.md).

## Surface réseau (ports ouverts)

Ports ouverts dans le firewall NixOS (`networking.firewall`) :

| Port | Proto | Service | Portée |
|---|---|---|---|
| 22 | TCP | sshd (**clé uniquement**) | LAN + tailnet ; pas de forward WAN ; fail2ban |
| 53 | TCP/UDP | AdGuard Home (DNS) | LAN + tailnet |
| 80 / 443 | TCP | Traefik | LAN ; exposé au WAN via redirection routeur (ACME DNS-01) |
| 8080 | TCP | UniFi (inform) | LAN / IoT |
| 22000 | TCP/UDP | Syncthing | LAN + tailnet |
| 10001, 3478 | UDP | UniFi (discovery / STUN) | LAN / IoT |
| 1883 | TCP | Mosquitto MQTT | **`br-iot` uniquement** (+ loopback ; fermé LAN/tailnet) |
| 1400 | TCP | Home Assistant — rappels d'abonnement UPnP Sonos (SoCo `EVENT_LISTENER_PORT`) | **`br-iot` uniquement** |
| 8123 | TCP | Home Assistant — média/TTS tirés par Sonos et Cast | **`br-iot` uniquement** (l'accès humain passe par Traefik) |
| 5353 | UDP | mDNS / zeroconf (découverte) | **`br-iot` uniquement** |
| 1900 | UDP | SSDP / UPnP (découverte) | **`br-iot` uniquement** |
| forward AirVPN | TCP/UDP | qBittorrent (port d'écoute) | interface `wg0` seule |

## Traefik (reverse proxy)

`networking/traefik/{options,static,dynamic}.nix`

- Entrypoints : HTTP 80 → redirection HTTPS, HTTPS 443 sur `lanIp`, et un
  entrypoint **`metrics`** `127.0.0.1:8083` (Prometheus).
- ACME via dnsChallenge Cloudflare (secret `cloudflare.age`).
- Middlewares : `secureHeaders` (HSTS, nosniff, frame-options), `ratelimit`
  (150 req/s avg, burst 300), `authelia` (forward auth) et `stripAuthHeaders`
  (supprime tout `Remote-*` client avant le forwardAuth).
- `traefik.services.<name>` (option custom) avec `methods` : la route publique
  de **ntfy est restreinte à `GET/HEAD/OPTIONS`** (écriture réservée aux
  publishers locaux en `localhost:2586`, hors Traefik).
- TLS hardening : minVersion TLS 1.2, ciphers ECDHE.
- Dashboard protégé par Authelia ; `serversTransports.insecure` pour backends
  self-signed (UniFi).
- ⚠️ **Première émission ACME d'une nouvelle route** : le défi DNS-01 peut
  échouer au premier essai (`403 unauthorized :: No TXT record found at
  _acme-challenge.<nom>`) sans que Traefik ne réessaie de lui-même — la route
  sert alors un certificat invalide et `curl -k` **masque** le problème. Vécu le
  2026-09-29 sur `ha.hyper.logikdev.fr`. Remède : `systemctl restart traefik`,
  qui relance la tentative (réussie au second essai). Toujours valider une
  nouvelle route **sans** `-k`, ou avec `%{ssl_verify_result}`.

## Authelia (SSO + 2FA)

`security/authelia.nix` — forwardAuth pour `*.logikdev.fr`. Postgres
(`authelia-main`). Politique (`access_control`) :

| Source | Politique |
|---|---|
| `192.168.10.0/24` (LAN) + `100.64.0.0/10` (tailnet) | `one_factor` (login sans 2FA) |
| tout le reste (WAN) | `two_factor` |
| défaut | `deny` |

Hors Authelia (auth applicative, clients natifs) : **Immich, Jellyfin,
Vaultwarden, Home Assistant, ntfy**. Détails : [security.md](security.md#authentification-web-authelia).

## AdGuard Home (DNS)

`networking/adguard.nix` — port 3000 (traefik `dns`)

- Résolveur principal (`nameservers = [ "127.0.0.1", "9.9.9.9" ]`, `resolved`
  désactivé). Le `9.9.9.9` est un secours si AdGuard tombe (non filtré).
- Upstreams **DNS-over-TLS** : `tls://dns.quad9.net` + `tls://dns10.quad9.net`
  (bootstrap `9.9.9.9` / `149.112.112.112`), DNSSEC activé.
- Rewrites `*.hyper.logikdev.fr` → `lanIp`.
- Firewall : UDP/TCP 53.

## fail2ban

`security/fail2ban.nix` — jail `sshd` (backend journal), ban escalating.
Ignore loopback, les deux sous-réseaux LAN et le CGNAT Tailscale. Métriques
exposées à Prometheus (exporter `fail2ban`, port 9191).

## MQTT (mosquitto)

`networking/mqtt/{mosquitto,zigbee2mqtt}.nix`

- Listener `1883` **restreint à l'interface `br-iot`** (loopback toujours
  autorisé) : zigbee2mqtt (loopback), rankoder (loopback), Home Assistant (VM
  sur le bridge IoT). Fermé sur LAN/tailnet/management.
- Auth obligatoire (pas d'anonyme). Comptes : `zigbee2mqtt` (ACL
  `readwrite zigbee2mqtt/#`), `homeassistant` (partagé avec rankoder, ACL
  `readwrite #`). Mot de passe dans agenix.
- **Pas encore de TLS** ; durcissement (comptes distincts + ACL + TLS 8883) =
  audit SEC-3b.

## UniFi

`networking/unifi.nix` — contrôleur UniFi + MongoDB-ce. Firewall 8080 + UDP
10001/3478. Backend Traefik en HTTPS self-signed (`insecureSkipVerify`).
Sauvegarde via les `.unf` auto (copie live, contrôleur non arrêté).

## DDNS (Cloudflare)

`networking/ddns.nix` — `cf-ddns` (input `Logik-Dev/cf-ddns`), timer toutes les
5 min, secret `ddns.env`. Maintient l'enregistrement DNS public de l'IP WAN.

## Tailscale (VPN mesh)

`networking/tailscale.nix`

- **hyper** : `useRoutingFeatures = "both"`, **subnet router**
  (`--advertise-routes=192.168.10.0/24,192.168.21.0/24`) ; **pas de `--ssh`**
  (l'admin passe par sshd clé-only, pas par Tailscale SSH).
- **sonicmaster** : client `--accept-routes`.
- **m4** (darwin) : `overrideLocalDns`, known network services (Thunderbolt/Wi-Fi).
- Auth key via agenix (`tailscale.age`). ACL : [tailscale-acl.md](tailscale-acl.md).

## VPN torrent (AirVPN → qBittorrent)

`features/downloads/{vpn,qbittorrent,cross-seed,freeleech-farmer}.nix` — doc complète :
[torrent-vpn.md](torrent-vpn.md)

- **Network namespace dédié `vpn`** : wg0 y est déplacé
  (`interfaceNamespace`), la socket de transport restant côté hôte. La seule
  route par défaut du namespace est le tunnel → **fail-closed structurel**, plus
  aucune règle de pare-feu à maintenir correcte. MTU 1320.
- Y vivent qBittorrent, Prowlarr, cross-seed et freeleech-farmer, placés par
  unité (`vpn.airvpn.netns.services`) et non plus par UID.
- Frontière : veth `10.200.0.0/30` — `10.200.0.1` côté hôte, `10.200.0.2` côté
  namespace. Traefik joint les WebUI sur `.2` ; `8989`/`7878` (Sonarr/Radarr)
  sont ouverts **sur la veth uniquement**. Table nft `vpn_guard` dans le
  namespace qui épingle la veth à son pair.
- DNS : les services résolvent via `10.128.0.1` (résolveur AirVPN, **dans le
  tunnel**) ; `/etc/netns/vpn/resolv.conf` pointe sur AdGuard par la veth et
  sert uniquement à l'**amorçage** (`wg set … endpoint` résout dans le namespace
  avant que le tunnel existe). Le MagicDNS Tailscale de l'hôte n'entre plus en
  jeu pour ces services.
- Port forward AirVPN (TCP+UDP) → port d'écoute qBittorrent, dont l'interface
  réseau doit rester fixée sur `wg0`.
- ⚠️ **Aucune supervision** du tunnel à ce jour : une panne ne produit ni unité
  en échec ni alerte (vécu — un cycle d'ordonnancement systemd a supprimé le job
  de démarrage au boot). Voir `docs/vpn-netns-plan.md`.

## SSH

`networking/ssh.nix`

- NixOS : `pam.sshAgentAuth`, pas de root login, pas d'auth mot de passe
  (`PasswordAuthentication=false`, `KbdInteractiveAuthentication=false`).
- Darwin (m4) : sshd **désactivé** ; ControlMaster 60m côté client.
- homeManager : alias `h` → hyper (lanIp), `ogms` → serveur distant ; sur darwin
  `zellij attach ssh` via RemoteCommand.

## VLANs & interfaces (hyper)

`hosts/hyper/ifnames.nix`

- `management` — IP statique `192.168.10.100/24`, GW `192.168.10.1`.
- `vms` — trunks VLAN 21/100/200.
- `br-iot` — bridge sur vlan21, `192.168.21.241/24` (Home Assistant VM).
- NetworkManager désactivé sur hyper.

**Filtrage inter-VLAN** (`hosts/hyper/inter-vlan-firewall.nix`, SEC-14) :
`ip_forward` est à 1 (posé par Tailscale) et la chaîne FORWARD est en `policy
ACCEPT`, `networking.firewall` ne filtrant que l'INPUT. Une chaîne `iot-forward`
appendue à FORWARD pour tout ce qui entre par `br-iot` ferme le mouvement
latéral : les réponses aux flux ouverts depuis le LAN passent
(`ESTABLISHED,RELATED`), les nouvelles connexions vers `192.168.10.0/24`,
`10.88.0.0/16` (podman) et `10.200.0.0/30` (veth du netns `vpn`) sont *droppées*,
le reste retombe sur la politique — l'egress n'est pas touché.

Deux limites assumées : **IoT → tailnet n'est pas couvert** (`ts-forward` passe
avant et accepte tout ce qui sort par `tailscale0` — cela relève des ACL
Tailscale), et la règle est **IPv4 seulement** (aucune route IPv6 sur hyper hors
`tailscale0`). Détail et sondes de vérification :
[security.md](security.md#routage-inter-vlan-filtré-sec-14--corrigé).

Noter enfin que `br_netfilter` n'est pas chargé : le trafic **bridgé** vers la VM
(`vnet0`) ne traverse aucune règle, le port 8123 de Home Assistant reste donc
joignable sans filtre depuis vlan21 — c'est intrinsèque au bridge, et ça se
referme avec la migration de HA en natif.

## Hetzner Storage Box

`storage/hetzner-storagebox.nix`

- SFTP offsite pour restic + pgBackRest.
- 3 types de host keys pinés (ed25519/rsa/ecdsa) car pgBackRest utilise libssh2.
- SSH extraConfig system-wide (Port 23, IdentityFile agenix).
- Clone postgres-owned de la clé (`hetzner-storagebox-pg`) pour pgBackRest.
