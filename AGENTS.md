# AGENTS.md

## Architecture

- **flake-parts** + **import-tree** — modules are auto-discovered from `modules/`. No `default.nix` import files needed; just drop a `.nix` anywhere and set `flake.modules.{nixos,darwin,homeManager}.<name>.imports`.
- **Dendritic pattern**: every module file writes into `flake.modules.*.<name>.imports` instead of using traditional `imports = [ ./... ]`. Host configs compose by appending to those named lists.
- Three hosts: `hyper` (x86_64-linux, production server), `sonicmaster` (x86_64-linux, media server), `m4` (aarch64-darwin, laptop).
- User config constants at `modules/features/system/constants.nix:20-31` (domain, email, GPG/SSH keys).

## Commands

| Action | Command |
|---|---|
| Build/check all | `nix flake check` |
| Format | `nix fmt` (auto via jj pre-commit hook) |
| Deploy to hyper | `nix run .#hyper -- switch` |
| Deploy to m4 | `nix run .#m4 -- switch` |
| Deploy to sonicmaster | `nix run .#sonicmaster -- switch` |
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

## Module conventions

- Feature modules under `modules/features/<category>/<name>.nix`.
- Each module sets `flake.modules.{nixos,darwin,homeManager}.<name>`.
- Host-specific config in `modules/hosts/<hostname>/` — `configuration.nix` (system), `home.nix` (home-manager). For hyper: `disko.nix` for disk partitioning.
- home-manager modules use the `homeManager` module class (e.g. `flake.modules.homeManager.dev`).
- `flake.modules.nixos.common` is included in every NixOS host; `flake.modules.darwin.common` for darwin; `flake.modules.homeManager.common` for all home-manager configs.
- Traefik services declare via `traefik.services.<name> = { port = ...; }` option (see `modules/features/networking/traefik.nix`).
- State versions: all pinned to `25.05` (both nixos and home-manager), darwin state version `5`.

## Known quirks

- `system.stateVersion` for darwin is an int (`5`), not a string — set in `modules/lib/+mk-os.nix:41`.
- `home-manager.useGlobalPkgs = true` on darwin (set in `modules/hosts/m4/home.nix:22`).
- nixd uses `nixpkgs=${inputs.nixpkgs}` nixPath (`modules/features/system/nix.nix:7`).
- git repos track both `.jj/` (Jujutsu) and `.git/`. Don't assume `git` is the only VCS.
- CI: none (no `.github/workflows`). Relies on local `nix flake check`.
- Formatting is automatic: jj pre-commit hook runs `nix fmt` on every commit.
