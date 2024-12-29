{
  inputs,
  homelab,
  lib,
  ...
}:

let
  getModules =
    host: target:
    lib.pipe host.modules [
      (map (mod: ../modules/${mod}/${target}.nix))
      (lib.filter (path: builtins.pathExists path))
    ];

  incusModules =
    host:
    (
      if host.platform == "lxc" then
        [ "${inputs.nixpkgs}/nixos/modules/virtualisation/lxc-container.nix" ]
      else if host.platform == "vm" then
        [ "${inputs.nixpkgs}/nixos/modules/virtualisation/lxd-virtual-machine.nix" ]
      else
        [ ]
    );

  nixosModules =
    host:
    (getModules host "nixos")
    ++ [
      ./common/nixos.nix
      ./${host.hostname}/nixos.nix
    ]
    ++ (incusModules host);

  hmModules =
    host:
    (getModules host "hm")
    ++ [
      ./common/hm.nix
      ./${host.hostname}/hm.nix
    ];

  mkHost =
    host:
    inputs.nixpkgs.lib.nixosSystem {
      system = host.system;
      specialArgs = {
        inherit homelab host inputs;
      };
      modules = (nixosModules host) ++ [
        inputs.sops-nix.nixosModules.sops
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager = {
            sharedModules = [
              inputs.sops-nix.homeManagerModules.sops
            ];
            useGlobalPkgs = true;
            useUserPackages = true;
            users.${homelab.username} = {
              imports = (hmModules host);
            };
            extraSpecialArgs = {
              inherit homelab host;
            };
          };
        }
      ];

    };
in
lib.mapAttrs (name: value: (mkHost value)) homelab.hosts
