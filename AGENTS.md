# AGENTS.md

## Architecture

- **flake-parts** + **import-tree** — modules are auto-discovered from `modules/`. No `default.nix` import files needed; just drop a `.nix` anywhere and set `flake.modules.{nixos,darwin,homeManager,generic}.<name>.imports`.
- **Dendritic pattern**: every module file writes into `flake.modules.*.<name>.imports` instead of using traditional `imports = [ ./... ]`. Host configs compose by appending to those named lists.
- Four module classes: `nixos` (NixOS system), `darwin` (macOS system), `homeManager` (home-manager user), `generic` (cross-OS constants/options via `generic.constants`).
- Three hosts: `hyper` (x86_64-linux, production server), `sonicmaster` (x86_64-linux, media server), `m4` (aarch64-darwin, laptop).
- User config constants at `modules/features/system/constants.nix:20-48` (domain, email, GPG/SSH keys, `hosts.hyper` IPs/MACs/storageBox, `media.gid`).
- Factories in `modules/lib/`:
  - `+mk-os.nix` — `flake.lib.mk-os.{linux,darwin}`: wraps `nixosSystem`/`darwinSystem`.
  - `+mk-home.nix` — `flake.lib.mk-home.{userOnHost,logikdevOnHost}`: builds `homeManagerConfiguration` from a host's system config.
  - `+mk-host.nix` — `flake.lib.mk-host`: one-call factory that builds `homeConfigurations."logikdev@<host>"` and injects home-manager imports into the host's `flake.modules.<cls>.<host>.imports`. Takes `{ host, osClass, modules, useGlobalPkgs, useUserPackages }`.
  - `user.nix` — `flake.factory.user`: creates user modules for darwin/nixos (fish shell, hashedPasswordFile, conditional groups).

## Commands

| Action | Command |
|---|---|
| Build/check all | `nix flake check` |
| Format | `nix fmt` (auto via jj pre-commit hook) |
| Deploy to hyper | `nix run .#hyper -- switch` |
| Deploy to m4 | `nix run .#m4 -- switch` |
| Deploy to sonicmaster | `nix run .#sonicmaster -- switch` |
| Deploy (nh alias) | `nh os switch` (or `nrs` for nixos-rebuild) |
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

## Known quirks

- `system.stateVersion` for darwin is an int (`5`), not a string — set in `modules/lib/+mk-os.nix:41`.
- `home-manager.useGlobalPkgs = true` on darwin + sonicmaster — set via `flake.lib.mk-host` in `modules/lib/+mk-host.nix:20`.
- nixd uses `nixpkgs=${inputs.nixpkgs}` nixPath (`modules/features/system/nix.nix:7`).
- git repos track both `.jj/` (Jujutsu) and `.git/`. Don't assume `git` is the only VCS.
- CI: none (no `.github/workflows`). Relies on local `nix flake check`.
- Formatting is automatic: jj pre-commit hook runs `nix fmt` on every commit.