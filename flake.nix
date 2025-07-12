{
  description = "NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/25.05";
    nixpkgs-master.url = "github:nixos/nixpkgs";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs-master";
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
    inputs@{ self, nixpkgs, ... }:
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

      # rebuild-target
      rebuildTarget = pkgs.callPackage ./scripts/rebuild-target.nix { };

      # sops config file
      sopsConfig = pkgs.callPackage ./scripts/sops-config.nix { };

      # image-builder
      imageBuilder = pkgs.callPackage ./scripts/image-builder.nix { };

      # copy sops config file and convert it to yaml
      copySopsConfig = pkgs.writeShellApplication {
        name = "copy-sops-config";
        text = ''
          ${pkgs.json2yaml}/bin/json2yaml ${sopsConfig} ./.sops.yaml
        '';
      };
    in

    {
      apps.${system} = {
        # image-builder
        image-builder = {
          type = "app";
          program = "${imageBuilder}/bin/image-builder";
        };

        # generate .sops.yaml with 'nix run .#sops-config-gen'
        sops-config-gen = {
          type = "app";
          program = "${copySopsConfig}/bin/copy-sops-config";
        };

        # add new machine with 'nix run .#machine add <hostname>'
        machine-add = {
          type = "app";
          program = "${machineAdd}/bin/machine-add";
        };

        # rebuild remote host with 'nix run .#rebuild-target <hostname>'
        rebuild-target = {
          type = "app";
          program = "${rebuildTarget}/bin/rebuild-target";
        };
      };

      packages.${system}.vm-base = self.nixosConfigurations.virtual-machine.config.system.build.qemuImage;

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
            specialArgs = {
              inherit
                inputs
                hosts
                hetzner_user
                domain
                username
                ;
              hostname = "nixos";
            };
            modules = [
              ./machines/common
              "${inputs.nixpkgs}/nixos/modules/virtualisation/lxc-container.nix"
            ];
          };

          # LXD Virtual Machine Image
          virtual-machine = lib.nixosSystem {
            inherit system;
            specialArgs = {
              inherit
                inputs
                hosts
                domain
                hetzner_user
                username
                ;
              hostname = "nixos";
            };
            modules = [
              ./machines/common
              "${inputs.nixpkgs}/nixos/modules/virtualisation/lxd-virtual-machine.nix"
            ];
          };
        };
    };
}
