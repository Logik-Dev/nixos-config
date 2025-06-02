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
      lib = nixpkgs.lib;
      system = "x86_64-linux";
      hosts = (import ./modules/homelab { inherit lib; }).config.hosts;
    in
    {
      nixosConfigurations = {
        # LXD Container Image
        container = lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs hosts; };
          modules = [
            ./machines/common
            "${inputs.nixpkgs}/nixos/modules/virtualisation/lxc-container.nix"
          ];
        };

        # LXD Virtual Machine Image
        virtual-machine = lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs hosts; };
          modules = [
            ./machines/common
            "${inputs.nixpkgs}/nixos/modules/virtualisation/lxd-virtual-machine.nix"
          ];
        };

        # Hyper
        hyper = lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs hosts;
          };
          modules = [
            ./machines/common
            ./machines/hyper
          ];
        };

        borg = lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs hosts; };
          modules = [
            ./machines/common
            ./machines/borg
          ];
        };

        dns = lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs hosts; };
          modules = [
            ./machines/common
            ./machines/dns
          ];
        };

        docker = lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs hosts; };
          modules = [
            ./machines/common
            ./machines/docker
          ];
        };

        medias = lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs hosts; };
          modules = [
            ./machines/common
            ./machines/medias
          ];
        };

        proxy = lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs hosts; };
          modules = [
            ./machines/common
            ./machines/proxy
          ];
        };

        security = lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs hosts; };
          modules = [
            ./machines/common
            ./machines/security
          ];
        };
      };
    };
}
