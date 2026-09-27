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
- Stack torrent : `modules/features/downloads/{vpn,qbittorrent,cross-seed,freeleech-farmer}.nix` — qBittorrent natif derrière AirVPN (wg0, table 4242, kill-switch nft par UID, port forward 51413) + cross-seed (ratio auto via cross-seeding) + freeleech-farmer (auto-grab freeleech Torznab → catégorie `freeleech`). Secrets : `cross-seed-secrets.json.age` (partagé). Doc complète : `docs/torrent-vpn.md`.
- Stack musique/voix : **hors dépôt** (Home Assistant = VM libvirt sur hyper, cf. `modules/hosts/hyper/libvirt.nix`). Spotify Famille multi-comptes via **Music Assistant** (add-on HAOS) : routage par `area_id` (script HA `musique_personne`), plugin **Spotify Connect** (Soloist), pipeline **Assist FR** (STT/TTS cloud). Doc complète : `docs/music-home.md`.

## Commands

| Action | Command |
|---|---|
| Build/check all | `nix flake check` (treefmt + checks d'éval des hôtes du système courant) ; `nix flake check --all-systems --no-build` pour tout évaluer |
| Format | `nix fmt` (nixfmt + deadnix + statix, auto via jj pre-commit hook) |
| Deploy to hyper | `nh os switch --hostname hyper --target-host logikdev@hyper --build-host logikdev@hyper` (depuis m4) |
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
- Large modules split into subdirectories following the neovim/nixvim pattern (e.g. `traefik/{options,static,dynamic}.nix`, `pgbackrest/{settings,services,secrets}.nix`, `restore-drill/{lib,restic-check,...}.nix`, `mqtt/{mosquitto,zigbee2mqtt}.nix`).
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
- `notify.services` accepts any string and the module itself creates the unit (`onFailure` wiring), so a typo yields an empty, never-started unit and a silent alert (cf. audit P0-3/FAC-5). Cross-check names against real units; an eval-time assertion is not viable.
- `nixos-rebuild switch` restarts changed *active* units; a running drill oneshot (e.g. `restic-read-data`, up to 6h) will block activation until it finishes. `sudo systemctl stop restic-read-data` first if a switch hangs.
- After adding a `backups.sources.<name>`, trigger its backups (`systemctl start restic-backups-<name>-{usb,hetzner}`) — otherwise the sftp exporter has no repo to read and alerts `ResticExporterDown` until the nightly run.
- A `restic` backup killed mid-run (e.g. a `nixos switch` during the nightly job) leaves a **stale exclusive lock**; the next run's pre-start `restic cat config` then fails and it retries `restic init` → `config file already exists` and the job fails silently until the repo goes stale. Fix: `restic -r <repo> unlock` (env from `/run/agenix/restic.env`), then re-run the job.
- VPN torrent : le transport WireGuard porte `fwMark 0x4242`. Sans lui, le kill-switch nft droppe les handshakes (paquets noyau générés par WireGuard). Ne jamais retirer `meta mark 0x4242 accept` ni la règle `ip rule fwmark 0x4242 lookup main pref 50`.
- DNS de hyper = **Tailscale MagicDNS** (`100.100.100.100`) : les UIDs torrent ont une exception scopée vers la table 52 (`vpn.airvpn.tailscaleNetworksV4/V6`) + kill-switch, sinon leurs requêtes DNS partent dans wg0 → `EAI_AGAIN` sur les trackers. Ne jamais mettre `100.64.0.0/10` dans `lanNetworks` (règle globale vers `main` = mesh/SSH cassés). Ne pas binder qBittorrent sur `wg0` (casse MagicDNS ; le kill-switch suffit).
- Prowlarr est un `DynamicUser` : `vpn-policy-routing`/`vpn-killswitch` sont `after`/`partOf` `prowlarr.service` pour résoudre son UID (sinon il n'est ni routé ni filtré au boot).
- Un `.conf` AirVPN contient la clé privée : ne jamais le committer (`.gitignore` → `AirVPN_*.conf`) ; si exposé (Nix store, git), rotater la clé.
- Formatting is automatic: jj pre-commit hook runs `nix fmt` on every commit.