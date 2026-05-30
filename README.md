# Homelab NixOS

Fully automated NixOS configuration for my homelab, built with `flake-parts` + `import-tree` using a dendritic module pattern.

## Hosts

| Host | Arch | Role |
|---|---|---|
| `hyper` | x86_64-linux | Production server |
| `sonicmaster` | x86_64-linux | Media server |
| `m4` | aarch64-darwin | Laptop |

## Deploy

```bash
nix run .#hyper -- switch      # production
nix run .#sonicmaster -- switch # media
nix run .#m4 -- switch          # laptop (darwin)
nix flake check                 # validate all configs
```

## Secrets

Managed via [agenix](https://github.com/ryantm/agenix) + [agenix-rekey](https://github.com/oddlama/agenix-rekey) with Yubikey as primary identity.

Encrypted `.age` files in `secrets/hosts/<hostname>/`. To add a new secret:

```bash
cp <plaintext> secrets/hosts/<hostname>/<name>.age
# edit modules to reference config.age.secrets.<name>
agenix-rekey
```

Rekeyed outputs committed to `secrets/rekeyed/` for target hosts.

## Modules

Feature modules live under `modules/features/<category>/<name>.nix`, host config under `modules/hosts/<hostname>/`. Each module writes into `flake.modules.{nixos,darwin,homeManager}.<name>.imports` — just drop a `.nix` file, no `default.nix` needed.

## VCS

[Jujutsu](https://github.com/jj-vcs/jj) (`jj`) — the `.jj/` directory is managed by jj alongside `.git/`.
