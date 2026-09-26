# Le pattern modulaire (dendritique)

Le flake utilise **flake-parts** + **import-tree** pour auto-découvrir les modules
depuis `modules/`. Aucun fichier `default.nix` d'import n'est nécessaire : il suffit
de déposer un fichier `.nix` n'importe où sous `modules/` et de peupler
`flake.modules.{nixos,darwin,homeManager,generic}.<name>.imports`.

## Les 4 classes de modules

| Classe | Scope | Inclusion automatique |
|---|---|---|
| `nixos` | Système NixOS (Linux) | `nixos.common` dans chaque hôte NixOS |
| `darwin` | Système macOS (nix-darwin) | `darwin.common` dans chaque hôte darwin |
| `homeManager` | Configuration utilisateur (home-manager) | `homeManager.common` dans tous les home-manager |
| `generic` | Constants/options cross-OS | `generic.constants` inclus dans les 3 via `*.common.imports` |

## Le pattern dendritique

Chaque fichier de module écrit dans `flake.modules.<classe>.<nom>.imports` au lieu
d'utiliser `imports = [ ./... ]` traditionnel. Les hôtes composent leur config en
ajoutant à ces listes nommées.

### Exemple simple (module body direct)

```nix
# modules/features/system/audio.nix
{
  flake.modules.nixos.audio = {
    services.pipewire.enable = true;
    # ...
  };
}
```

L'hôte l'importe par son nom : `with inputs.self.modules.nixos; [ audio ... ]`.

### Exemple avec imports (sous-modules)

```nix
# modules/features/dev/default.nix
{ inputs, ... }:
{
  flake.modules.homeManager.dev.imports = with inputs.self.modules.homeManager; [
    dev-direnv
    git
    jj
  ];
}
```

### Exemple de split (neovim/nixvim)

Un grand module est éclaté en plusieurs fichiers qui peuplent tous le même slot :

```nix
# modules/features/neovim/nixvim/options.nix
{ ... }: {
  flake.modules.nixos.neovim.imports = [ options ];
  options = { lib, pkgs, ... }: { ... };
}
```

Autres splits : `traefik/{options,static,dynamic}.nix`,
`pgbackrest/{settings,services,secrets}.nix`,
`restore-drill/{lib,restic-check,restore-canary,postgres-drill,read-data}.nix`,
`mqtt/{mosquitto,zigbee2mqtt}.nix`, `disko/{default,system-disks,data-disks}.nix`.

## Factories (`modules/lib/`)

### mk-os (`+mk-os.nix`)

`flake.lib.mk-os.{linux,darwin}` — wraps `nixosSystem`/`darwinSystem`. Injecte
`nixpkgs.config.allowUnfree`, `hostName`/`hostPlatform` `mkDefault`, et
`system.stateVersion`.

### mk-home (`+mk-home.nix`)

`flake.lib.mk-home.{userOnHost,logikdevOnHost}` — builds
`homeManagerConfiguration` en partageant `pkgs` avec la config système de l'hôte.

### mk-host (`+mk-host.nix`)

`flake.lib.mk-host` — factory one-call qui produit
`homeConfigurations."logikdev@<host>"` ET injecte les imports home-manager dans
`flake.modules.<cls>.<host>.imports`.

```nix
# modules/hosts/hyper/home.nix
{ inputs, ... }:
let
  host = (inputs.self.lib.mk-host {
    host = "hyper";
    modules = with inputs.self.modules.homeManager; [ jj dev ];
  });
  flake.homeConfigurations."logikdev@hyper" = host.homeConfig.config;
  flake.modules.nixos.hyper.imports = [ host.homeImport ];
in { inherit flake; }
```

Le `let`-binding paresseux est nécessaire pour briser la cyclicité avec
`nixosConfigurations.<host>` (Nix lazy-évalue).

### factory.user (`user.nix`)

`flake.factory.user username isAdmin` — crée les modules utilisateur pour
darwin/nixos (fish shell, hashedPasswordFile, groupes conditionnels via
`lib.filter hasGroup`).

## Secrets auto-loader

`modules/features/security/secrets.nix` scanne `secrets/hosts/<hostname>/*.age`
et enregistre automatiquement chaque fichier comme
`age.secrets."<name>".rekeyFile`. Ajouter un secret = déposer un `.age` + rekey.

## Constants globaux (`generic.constants`)

`modules/features/system/constants.nix` déclare `options.constants` (attrsOf
unspecified) et peuple `config.constants` :

- `domain` — domaine principal (`logikdev.fr`)
- `users.logikdev` — fullname, username, flakeDir, email, sshKey, sshKeyMac
- `hosts.hyper` — lanIp, gateway, prefixLength, mac.{management,vms}, storageBox.{user,host}
- `media.gid` — GID du groupe media (991)

Accessible partout via `config.constants.*` car `generic.constants` est inclus
dans `nixos.common`, `darwin.common`, et `homeManager.common`.

## Traefik services + glance

`traefik.services` est une option NixOS custom (`traefik/options.nix`) qui décrit
un attrsOf de services. Chaque service a : `host`, `port`,
`protocol`, `enableAuthelia`, `insecureSkipVerify`, `category`, `icon`, `title`.

Traefik génère automatiquement les routers/services depuis cette option
(`traefik/dynamic.nix`).

Glance (`monitoring/glance.nix`) auto-génère ses widgets monitor depuis
`config.traefik.services` filtré par `category` : chaque service avec une
catégorie non-null devient un site entry dans le widget correspondant. URL et
check-url sont dérivés du service key + host + domain + port.