# AGENTS.md

## Architecture

- **flake-parts** + **import-tree** — modules are auto-discovered from `modules/`. No `default.nix` import files needed; just drop a `.nix` anywhere and populate `flake.modules.{nixos,darwin,homeManager,generic}.<name>` (either a direct config assignment or an `.imports` list).
- **Dendritic pattern**: instead of traditional `imports = [ ./... ]`, modules write into the flake-parts `flake.modules.<class>.<name>` attrs — most assign the config directly (`flake.modules.nixos.audio = { ... }`), others compose via `.imports` (e.g. a `default.nix` listing sub-modules). Host configs compose by appending to those named lists.
- Four module classes: `nixos` (NixOS system), `darwin` (macOS system), `homeManager` (home-manager user), `generic` (cross-OS constants/options via `generic.constants`).
- Three hosts: `hyper` (x86_64-linux, production server), `sonicmaster` (x86_64-linux, media server), `m4` (aarch64-darwin, laptop).
- User config constants at `modules/features/system/constants.nix` (domain, email, SSH keys, `hosts.hyper` IPs/MACs/storageBox, `hosts.m4.tailscaleIp`, `media.gid`).
- Factories in `modules/lib/`:
  - `+mk-os.nix` — `flake.lib.mk-os.{linux,darwin}`: wraps `nixosSystem`/`darwinSystem`.
  - `+mk-home.nix` — `flake.lib.mk-home.{userOnHost,logikdevOnHost}`: builds `homeManagerConfiguration` from a host's system config.
  - `+mk-host.nix` — `flake.lib.mk-host`: one-call factory that builds `homeConfigurations."logikdev@<host>"` and injects home-manager imports into the host's `flake.modules.<cls>.<host>.imports`. Takes `{ host, modules, useGlobalPkgs, useUserPackages }`.
  - `user.nix` — `flake.factory.user`: creates user modules for darwin/nixos (fish shell, hashedPasswordFile, conditional groups).
- Stack torrent : `modules/features/downloads/{vpn,qbittorrent,cross-seed,freeleech-farmer}.nix` — qBittorrent natif derrière AirVPN, **isolé dans un network namespace dédié `vpn`** (wg0 déplacé dedans, veth `10.200.0.0/30`, fail-closed structurel : la seule route par défaut du namespace est le tunnel). Port forward 47594 (public=local). + cross-seed (ratio auto via cross-seeding) + freeleech-farmer (auto-grab freeleech Torznab → catégorie `freeleech`). Secrets : `cross-seed-secrets.json.age` (partagé). Doc complète : `docs/torrent-vpn.md` ; historique de la migration : `docs/vpn-netns-plan.md`.
- Stack musique/voix : **hors dépôt** (Home Assistant = VM libvirt sur hyper, cf. `modules/hosts/hyper/libvirt.nix`). Spotify Famille multi-comptes via **Music Assistant** (add-on HAOS) : routage par `area_id` (script HA `musique_personne`), plugin **Spotify Connect** (Soloist), pipeline **Assist FR** (STT/TTS cloud). Doc complète : `docs/music-home.md`.
- Stack livres : **Audiobookshelf** (module natif, DB/meta `/var/lib/audiobookshelf`, bibliothèques `/mnt/storage/medias/{books,audiobooks}` ; **pas d'Authelia** → apps natives) + **Bindery** (containeur podman `ghcr.io/vavallee/bindery`, `--network=host` + `--user=1000:991` + `--umask=0002`, config `/mnt/ultra/bindery`, `BINDERY_DOWNLOAD_ALLOW_LOOPBACK=1` car Prowlarr sur loopback). **Mount unique** `/mnt/storage/medias` aux chemins identiques à l'hôte : des binds séparés auraient des device IDs différents dans le conteneur → pas de hardlink (Bindery copierait, doublant le disque) ; en un seul mount l'import hardlink, et pas de remap qBittorrent/SABnzbd. Remplace **Readarr** (archivé 2025-06-27). Réutilise Prowlarr/qBittorrent/SABnzbd, aucun VPN. Backups : config seule (pas la bibliothèque).

## Commands

| Action | Command |
|---|---|
| Build/check all | `nix flake check` (treefmt + checks d'éval des hôtes du système courant) ; `nix flake check --all-systems --no-build` pour tout évaluer |
| Format | `nix fmt` (nixfmt + deadnix + statix, auto via jj pre-commit hook) |
| Deploy to hyper | `nh os switch --hostname hyper --target-host logikdev@hyper --build-host logikdev@hyper -e passwordless` (depuis m4 ; `-e passwordless` car hyper a sudo NOPASSWD, sinon nh réclame un mot de passe sudo sur un stdin non-TTY) |
| Deploy to m4 | `sudo darwin-rebuild switch --flake .#m4` (local) |
| Deploy to sonicmaster | `nh os switch --hostname sonicmaster` (local, sshd désactivé) |
| Enter devshell | `nix develop` |
| Rekey secrets | `nix run .#agenix-rekey` (from devshell) |

Always run `nix flake check` before committing.

## Secrets

- agenix + agenix-rekey with `storageMode = "local"`.
- Encrypted `.age` files live in `secrets/hosts/<hostname>/`.
- Master identity: Yubikey + age key at `~/.config/age/keys.txt`.
- `AGENIX_REKEY_PRIMARY_IDENTITY` exported in `.envrc` (direnv).
- `.sops.yaml` splits encryption keys per host regex pattern.
- To add a secret: create `<hostname>/<name>.age` and rekey.
- Secrets auto-discovered by `modules/features/security/secrets.nix` — drop a `.age` file in `secrets/hosts/<host>/` and it's automatically registered as `age.secrets."<name>".rekeyFile`.
- Secrets torrent : `airvpn-private.key` + `airvpn-psk.key` (auto-découverts). En runtime ils sont montés à `/run/agenix/<nom>` (et **non** `/run/agenix.d/<nom>`, qui contient les générations internes).

## Module conventions

- Feature modules under `modules/features/<category>/<name>.nix`.
- Each module sets `flake.modules.{nixos,darwin,homeManager,generic}.<name>`.
- Host-specific config in `modules/hosts/<hostname>/` — `configuration.nix` (system), `home.nix` (home-manager). For hyper: `disko/default.nix` (+ `system-disks.nix` + `data-disks.nix`) for disk partitioning.
- home-manager modules use the `homeManager` module class (e.g. `flake.modules.homeManager.dev`).
- `flake.modules.nixos.common` is included in every NixOS host; `flake.modules.darwin.common` for darwin; `flake.modules.homeManager.common` for all home-manager configs. `flake.modules.generic.constants` is included in all three via `*.common.imports`.
- Traefik services declare via `traefik.services.<name> = { port = ...; }` option (see `modules/features/networking/traefik/options.nix`). Extended with `category`/`icon`/`title` for glance dashboard integration.
- Large modules split into subdirectories following the neovim/nixvim pattern (e.g. `traefik/{options,static,dynamic}.nix`, `pgbackrest/{settings,services,secrets}.nix`, `restore-drill/{lib,restic-verify,postgres-drill}.nix`, `mqtt/{mosquitto,zigbee2mqtt}.nix`).
- Module arg order canon: `{ config, lib, pkgs, ... }`.
- State versions: all pinned to `25.05` (both nixos and home-manager), darwin state version `5`.

## Audit & suivi

- Audit complet (2026-09-24) et feuille de route multi-sessions dans `docs/audit-2026-09.md` — IDs `P0-*`/`SEC-*`/`MON-*`/`BAK-*`/`CLN-*`/`FAC-*`/`ADD-*`/`DOC-*`. Mettre à jour la colonne `Statut` + le journal de sessions à chaque correction.

## Known quirks

- `system.stateVersion` for darwin is an int (`5`), not a string — set in `modules/lib/+mk-os.nix:41`.
- Music Assistant (VM HA) : la recherche catalogue du provider Spotify peut se **bloquer** (ne renvoie que la bibliothèque) → l'intent média joue une radio TuneIn à la place. Fix : **reload du provider** (MA → Providers, ou API `config/providers/reload`). Détail : `docs/music-home.md` (§ Dépannage).
- `home-manager.useGlobalPkgs = true` on darwin + sonicmaster — set via `flake.lib.mk-host` in `modules/lib/+mk-host.nix:20`.
- nixd uses `nixpkgs=${inputs.nixpkgs}` nixPath (`modules/features/system/nix.nix:7`).
- git repos track both `.jj/` (Jujutsu) and `.git/`. Don't assume `git` is the only VCS.
- CI: none (no `.github/workflows`). Relies on local `nix flake check`.
- New `.nix` files must be `git add`-ed: the flake source is the git tree, so untracked files are invisible to `nix eval`/`nixos-rebuild` (import-tree won't see them either).
- import-tree skips files whose name starts with `_` — use that prefix for non-module helpers (e.g. `medias/lib/_servarr.nix`, `monitoring/lib/_ntfy.nix`) that are only pulled in via relative `import`.
- Chaque hôte NixOS charge `modules/hosts/<host>/facter.json` **s'il existe** (`system/hardware.nix`) ; sinon le rapport facter est vide et l'éval reste valide. Ajout d'un hôte : voir `docs/add-host.md`.
- `notify.services` accepts any string and the module itself creates the unit (`onFailure` wiring), so a typo *used to* yield an empty, never-started unit and a silent alert. It is now caught at eval: `notification.nix` asserts each entry is a real service (a ghost is all-defaults, so it must have a `description`, a `script` or a non-empty `serviceConfig` — cf. audit FAC-5). Still prefer real unit names (`authelia-main`, not `authelia`; `tailscaled`, not `tailscale`).
- `nixos-rebuild switch` restarts changed *active* units; a running drill oneshot (e.g. `restic-verify`, up to 6h) will block activation until it finishes. `sudo systemctl stop restic-verify` first if a switch hangs.
- After adding a `backups.sources.<name>`, trigger its backup (`systemctl start restic-backups-<name>`) so both repos (usb + hetzner) are created and the push metrics exist — otherwise `ResticRepoEmpty`/`ResticMetricsMissing` alert until the nightly run.
- A `restic` backup killed mid-run (e.g. a `nixos switch` during the nightly job) used to leave a **stale exclusive lock** and block every later run. The backup script now runs `restic -r <repo> unlock` before each backup, so it self-heals; if a repo still looks stuck, unlock manually (env from `/run/agenix/restic.env`).
- VPN torrent : **plus de `fwMark` ni de kill-switch nft** depuis la migration en network namespace. Le `fwMark 0x4242` n'était nécessaire *que* tant que le kill-switch vivait : la socket de transport WireGuard reste dans le namespace hôte (seule l'interface part dans le netns), donc ses paquets — générés par le noyau, sans `skuid` à matcher — tombaient sur le `drop` sans la marque. Piège vécu deux fois : `wg show` compte des octets « sent » même quand rien ne part ; le seul diagnostic fiable est `tcpdump -nni management udp port 1637`.
- Port forward AirVPN : le **port public** (celui que les pairs joignent) et le champ **`Local`** doivent être **identiques** et égaux à `vpn.airvpn.forwardedPort` (ex. 47594), sinon qBittorrent annonce un port fermé → injoignable (ratio ~0). Vérif : `sudo -u qbittorrent curl -s https://ifconfig.co/port/47594` → `reachable:true`.
- `dynamicEndpointRefreshSeconds` : `nl3.vpn.airdns.org` est un pool d'entry IP ; 300 s faisait changer le serveur/exit IP trop souvent (connexions pairs coupées). Réglé à 3600 s.
- Farmer freeleech : `freeleech-farmer.py` trie les candidats par **leechers** (upload potentiel) ; `FARMER_MIN_LEECHERS`, quotas (`MAX_ADDS=15`, `MAX_TOTAL_GB=300`, `CLEAN_DAYS=30`) et cadence 10 min.
- DNS de hyper = **Tailscale MagicDNS** (`100.100.100.100`), mais les services du netns VPN ne le voient pas : ils ont `nameserver 10.128.0.1` (résolveur AirVPN, **DNS enfin tunnelisé**) via un `BindReadOnlyPaths` sur `/etc/resolv.conf`, car **`NetworkNamespacePath` ne bind-monte PAS `/etc/netns/<ns>/*`** (seul `ip netns exec` le fait). Le `/etc/netns/vpn/resolv.conf` pointe lui sur AdGuard via la veth (`10.200.0.1`) : c'est le résolveur d'**amorçage**, indispensable parce que `wg set … endpoint` s'exécute *dans* le netns et doit résoudre `nl3.vpn.airdns.org` avant que le tunnel existe. Un bind raté ne fuite pas, il donne un timeout (`EAI_AGAIN`).
- Prowlarr est un `DynamicUser` — ce qui **ne pose plus de problème** : l'appartenance au netns est fixée par unité (`NetworkNamespacePath`) et ne dépend plus de résoudre un UID à l'exécution. Toute la gymnastique `after`/`partOf`/`wantedBy` sur `prowlarr.service` (et la fuite WAN qu'elle rattrapait quand le backup restic faisait `stop`/`start`) a disparu avec le kill-switch.
- Torrents cross-seed en `error` (`file_open ... .nfo ... Permission non accordée`) : `cross-seed.service` doit avoir `UMask=0002` pour créer les dossiers de liens en 2775 (sinon 2755, groupe `media` non inscriptible) ; qBittorrent doit pouvoir y créer le `.nfo` absent de la bibliothèque. cross-seed ne reprend pas les torrents en `error` de lui-même → les `resume` après correction des droits.
- Prowlarr (module nixpkgs) : ne **jamais** mettre de `dataDir` custom. Le module bind-monte le dir custom sur `/var/lib/private/prowlarr` et crée la source en `root:root 0700`, illisible par le `DynamicUser` → `Access to the path '/var/lib/prowlarr/config.xml' is denied`. Garder le défaut `/var/lib/prowlarr` (StateDirectory) et sauvegarder `/var/lib/private/prowlarr`. Les indexers/apps sont de toute façon en Postgres.
- **`systemctl --failed` vide ≠ boot sain.** Un cycle d'ordonnancement systemd fait *supprimer* un job de démarrage, sans aucune unité en échec : `wireguard-wg0` (que le module nixpkgs met `before network.target`) portait `after=adguardhome`, lui-même `after network.target` → le tunnel ne démarrait pas du tout au boot, `is-system-running` = `degraded` et `--failed` vide. Ne **jamais** réintroduire d'ordonnancement DNS sur `wireguard-wg0` : créer l'interface ne résout aucun nom, seule l'unité *peer* le fait et elle attend le DNS en interne (`WG_ENDPOINT_RESOLUTION_RETRIES=infinity`). Vérifier au boot : `journalctl -b` filtré sur « ordering cycle ».
- **Un service qui lie un listener au tunnel doit redémarrer avec lui.** qBittorrent énumère les interfaces au démarrage et ne se réattache jamais : si `wg0` est recréé sous lui, il n'écoute plus que sur `lo`/veth, le port forwardé devient injoignable et le ratio tombe à zéro **sans unité en échec**. D'où `partOf` + `wantedBy` sur `wireguard-wg0.service` (les deux : `partOf` seul ne remonte pas l'unité). Vérif : `ip netns exec vpn ss -tlnp | grep wg0`.
- **`checkReversePath` est du rpfilter iptables, pas un sysctl** (`firewall-iptables.nix`, chaîne `nixos-fw-rpfilter` en mangle/PREROUTING) : les règles iptables sont **par namespace**, donc il n'y en a aucune devant `wg0` dans le netns — rien à desserrer. Inutile aussi d'essayer de le durcir sur l'hôte : `services.tailscale.useRoutingFeatures = "both"` (`hosts/hyper/configuration.nix`) l'épingle à `"loose"` en définition simple. Deux définitions égales fusionnent, une différente casse l'éval.
- **Une option de liste alimentée par plusieurs modules doit avoir un défaut vide.** Un `default` n'est *pas* une définition : les contributions le **remplacent** au lieu de l'étendre. Vécu sur `vpn.airvpn.netns.services` (défaut `[qbittorrent prowlarr]` + contributions cross-seed/freeleech-farmer → les deux premiers disparaissaient du netns). Corollaire : `options.<…>.isDefined` est vrai dès qu'il existe un défaut — pour détecter une personnalisation, comparer la valeur au défaut.
- **qBittorrent doit avoir son interface réseau fixée sur `wg0`** (Options → Avancé, `Session\Interface=wg0`). Sinon il lie aussi un listener au device veth et y émet du trafic pair/DHT pour rien (~460 paquets après un restart du tunnel), que la table nft `vpn_guard` du namespace jette. Ce n'était **pas** conseillé avant la migration (le bind cassait MagicDNS) ; ça l'est depuis que le namespace résout par le tunnel. Le bind ne touche pas la WebUI, qui reste sur `*`. Si le compteur de `vpn_guard` se remet à monter, c'est ce réglage à vérifier.
- **NixOS préfixe le `script` d'une unité systemd par `set -e`** : un `set -uo pipefail` écrit ensuite ne l'annule PAS. Pour un script qui doit aller au bout malgré des échecs (typiquement un collecteur de métriques), commencer par **`set +e`** — sinon il s'arrête au premier échec et laisse les valeurs précédentes en place, donc une panne rapportée comme saine. Éviter aussi `-u` (une variable non liée tue le shell même sans `-e`).
- **Un dead-man sur métrique textfile doit tester la fraîcheur, pas `absent()`** : le collecteur textfile de node_exporter sert un `.prom` indéfiniment, donc un producteur planté laisse ses dernières valeurs exposées pour toujours. Comparer `time() - <horodatage écrit à chaque run>` (cf. `VpnMonitorMissing`).
- **Bindery met en cache sa config client au démarrage** : changer l'URL de qBittorrent/Prowlarr dans son UI ne prend effet qu'après `systemctl restart podman-bindery`.
- **Deux tests « évidents » qui mentent sur hyper** : un `curl` depuis hyper vers sa propre IP LAN passe par `lo` (accepté par le pare-feu) et ne prouve rien sur l'ouverture d'un port — tester depuis une autre machine ou lire `iptables -S` ; et Traefik n'écoute que sur `192.168.10.100`, donc `https://127.0.0.1` renvoie `000` sans que rien ne soit cassé.
- Un `.conf` AirVPN contient la clé privée : ne jamais le committer (`.gitignore` → `AirVPN_*.conf`) ; si exposé (Nix store, git), rotater la clé.
- Formatting is automatic: jj pre-commit hook runs `nix fmt` on every commit.