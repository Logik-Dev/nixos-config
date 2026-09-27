# Ajouter un hôte

Procédure complète pour ajouter une machine au flake (NixOS ou nix-darwin).
Voir aussi [modules-pattern.md](modules-pattern.md) pour le pattern modulaire.

## 1. Déclarer la configuration système

`modules/flake/osConfigurations.nix` liste explicitement les hôtes :

```nix
{ inputs, ... }:
let
  inherit (inputs.self.lib.mk-os) linux darwin;
  flake.nixosConfigurations.<host> = linux "<host>";
  # ou pour un Mac : flake.darwinConfigurations.<host> = darwin "<host>";
in
{ inherit flake; }
```

`flake.lib.mk-os` (`modules/lib/+mk-os.nix`) injecte `hostName`, `hostPlatform`,
`stateVersion` (`25.05` NixOS, `5` darwin) et `allowUnfree`.

## 2. Config système de l'hôte

Créer `modules/hosts/<host>/configuration.nix` :

```nix
{ inputs, ... }:
let
  flake.modules.nixos.<host>.imports =
    (with inputs.self.modules.nixos; [
      common          # socle : SSH, secrets, nix, hardware/facter, …
      logikdev        # utilisateur
      # + modules de features (adguard, tailscale, …)
    ])
    ++ [
      # config spécifique à l'hôte (réseau, disque, tailscale…)
    ];
in
{ inherit flake; }
```

> `flake.modules.nixos.common` active **sshd par défaut** (`mkDefault true`) ;
> le désactiver explicitement (`services.openssh.enable = false`) si l'hôte ne
> doit pas être joignable (cf. sonicmaster/m4).

Pour un hôte partitionné par disko, ajouter un module `modules/hosts/<host>/disko/…`
sur le modèle de `hosts/hyper/disko/{default,system-disks,data-disks}.nix`.

## 3. Home-manager de l'hôte

Créer `modules/hosts/<host>/home.nix` (factory `flake.lib.mk-host`) :

```nix
{ inputs, ... }:
let
  host = inputs.self.lib.mk-host {
    host = "<host>";
    useGlobalPkgs = true;      # darwin + sonicmaster
    useUserPackages = true;
    modules = with inputs.self.modules.homeManager; [ dev desktop ];
  };
  flake.homeConfigurations."logikdev@<host>" = host.homeConfig.config;
  flake.modules.nixos.<host>.imports = [ host.homeImport ];
in
{ inherit flake; }
```

## 4. Clé hôte dans agenix (**obligatoire**)

`security/agenix.nix` mappe chaque hôte à sa clé publique SSH :

```nix
hostKeys = {
  <host> = "ssh-ed25519 AAAA…";
};
```

Sans cette entrée, `age.rekey.hostPubkey = hostKeys.${hostname}` **casse l'éval**.
Récupérer la clé publique de l'hôte (`/etc/ssh/ssh_host_ed25519_key.pub`) après
une première install, ou la générer et la fournir.

## 5. Secrets

- Déposer/chiffrer les secrets sous `secrets/hosts/<host>/<nom>.age` :
  `agenix -e secrets/hosts/<host>/<nom>.age` (depuis le devshell).
- Auto-découverts par `security/secrets.nix` → `age.secrets."<nom>"`.
- Recalculer les sorties rekeyées : `nix run .#agenix-rekey`.
- Secrets usuels d'un hôte : `hashedPasswordFile` (user), `tailscale.age`
  (auth key), `restic.env`, et selon les features (`cloudflare.age`, …).

## 6. facter / matériel (optionnel)

`system/hardware.nix` charge `modules/hosts/<host>/facter.json` **s'il existe**
(sinon rapport facter vide). Pour un hôte physique, générer le rapport avec
[`nixos-facter`](https://github.com/nix-community/nixos-facter) et le committer.
L'éval reste valide sans ce fichier.

## 7. Finaliser

- **`git add`** tous les nouveaux fichiers (flakes ignorent les fichiers non
  suivis ; `import-tree` ne les verrait pas).
- Vérifier : `nix flake check --all-systems --no-build` (éval), puis déployer
  (voir [README](../README.md#deploy)).
- `home-manager.useGlobalPkgs = true` sur darwin + sonicmaster, sinon warning.
- `system.stateVersion` darwin est un **entier** (`5`) — déjà géré par `mk-os`.

## Pièges connus

- Oublier l'entrée `hostKeys` → échec d'éval (`attribute 'host' missing`).
- Nouveaux `.nix` non `git add`és → invisibles pour Nix/`import-tree`.
- hôte sans `facter.json` : OK, mais `hardware.*` non renseigné (à compléter à la main).
