# Architecture réseau (hôte hyper)

## Traefik (reverse proxy)

`networking/traefik/{options,static,dynamic}.nix`

- Entrypoints HTTP (80) → redirection HTTPS, HTTPS (443) sur `lanIp`
- ACME via dnsChallenge cloudflare (secret `cloudflare.age`)
- Middlewares : `secureHeaders` (HSTS, nosniff, frame-options), `ratelimit`
  (150 req/s avg, burst 300), `authelia` (forward auth)
- TLS hardening : minVersion TLS 1.2, cipher suites ECDHE seulement
- Dashboard protégé par Authelia
- Services déclarés via `traefik.services.<name>` (custom option)
- `serversTransports.insecure` pour backends self-signed (UniFi)

## AdGuard Home (DNS)

`networking/adguard.nix` — port 3000 (traefik `dns`)

- Résolveur DNS principal (`nameservers = [ "127.0.0.1" ]`, `resolved` désactivé)
- Upstreams : Quad9 (9.9.9.9), DNSSEC activé
- Rewrites `*.hyper.logikdev.fr` → `lanIp` (192.168.10.100)
- Firewall : UDP/TCP 53

## Tailscale (VPN mesh)

`networking/tailscale.nix`

- Hyper : `useRoutingFeatures = "both"`, advertise routes `192.168.10.0/24,192.168.21.0/24`
- Sonicmaster : client, `--accept-routes`
- M4 (darwin) : known network services (Thunderbolt/Wi-Fi)
- Auth key via agenix (`tailscale.age`)

## SSH

`networking/ssh.nix`

- NixOS : pam sshAgentAuth, no root login, no password auth
- Darwin : openssh, ControlMaster 60m sur m4
- homeManager : alias `h` → hyper (lanIp), `ogms` → serveur distant
- Sur darwin : `zellij attach ssh` automatiquement via RemoteCommand

## VLANs & interfaces (hyper)

`hosts/hyper/ifnames.nix`

- `management` (MAC fc:34:97:10:ca:04) — IP statique 192.168.10.100/24, GW 192.168.10.1
- `vms` (MAC 98:b7:85:00:8f:f2) — trunks VLAN 21/100/200
- `br-iot` — bridge sur vlan21, IP 192.168.21.241/24 (Home Assistant VM)
- NetworkManager désactivé sur hyper

## Hetzner Storage Box

`storage/hetzner-storagebox.nix`

- SFTP offsite pour restic + pgbackrest
- 3 types de host keys pinés (ed25519/rsa/ecdsa) car pgBackRest utilise libssh2
- SSH extraConfig system-wide (Port 23, IdentityFile agenix)
- Clone postgres-owned de la clé (`hetzner-storagebox-pg`) pour pgbackrest