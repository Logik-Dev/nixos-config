{
  description = "NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:nixos/nixpkgs";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cf-ddns = {
      url = "github:Logik-Dev/cf-ddns";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pushr = {
      url = "github:Logik-Dev/pushr";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-facter-modules.url = "github:numtide/nixos-facter-modules";
  };

  outputs =
    inputs@{ nixpkgs, ... }:
    let
      inherit (builtins.fromJSON (builtins.readFile ./special_args.json))
        username
        domain
        email
        hetzner_user
        ;
      lib = nixpkgs.lib;
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      hosts = (import ./modules/homelab { inherit lib; }).config.hosts;

      # machine-add script
      machineAdd = pkgs.callPackage ./scripts/machine-add.nix { };

      # sops config file
      sopsConfig = pkgs.callPackage ./scripts/sops-config.nix { };

      # copy sops config file and convert it to yaml
      copySopsConfig = pkgs.writeShellApplication {
        name = "copy-sops-config";
        text = ''
          ${pkgs.json2yaml}/bin/json2yaml ${sopsConfig} ./.sops.yaml
        '';
      };
    in

    {

      # generate .sops.yaml with 'nix run .#sops-config-gen'
      apps.${system} = {
        sops-config-gen = {
          type = "app";
          program = "${copySopsConfig}/bin/copy-sops-config";
        };
        machine-add = {
          type = "app";
          program = "${machineAdd}/bin/machine-add";
        };
      };

      nixosConfigurations =
        # machines
        builtins.mapAttrs (
          hostname: v:
          lib.nixosSystem {
            inherit system;
            specialArgs = {
              inherit
                hostname
                username
                email
                domain
                hetzner_user
                inputs
                hosts
                ;
            };
            modules = [
              ./machines/common
              ./machines/${hostname}
              ./modules/backups
            ];
          }
        ) hosts
        // {

          # LXD Container Image
          container = lib.nixosSystem {
            inherit system;
            specialArgs = { inherit inputs hosts hetzner_user; };
            modules = [
              ./machines/common
              "${inputs.nixpkgs}/nixos/modules/virtualisation/lxc-container.nix"
            ];
          };

          # LXD Virtual Machine Image
          virtual-machine = lib.nixosSystem {
            inherit system;
            specialArgs = { inherit inputs hosts hetzner_user; };
            modules = [
              ./machines/common
              "${inputs.nixpkgs}/nixos/modules/virtualisation/lxd-virtual-machine.nix"
            ];
          };
        };
    };
}
