{
  description = "NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/25.05";
    nixpkgs-master.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs-master";
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
    inputs@{
      self,
      nixpkgs,
      nixpkgs-master,
      ...
    }:
    let
      username = "logikdev";
      domain = "logikdev.fr";
      email = "logikdevfr@gmail.com";
      lib = nixpkgs.lib;
      system = "x86_64-linux";
      pkgsUnstable = import nixpkgs-master {
        inherit system;
        config.allowUnfree = true;
      };

    in

    {
      # Single server configuration
      nixosConfigurations.hyper = lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit
            username
            email
            domain
            inputs
            pkgsUnstable
            ;
          hostname = "hyper";
          hosts = { hyper = { ipv4 = "192.168.10.100"; }; };
        };
        modules = [
          ./machines/hyper
        ];
      };
    };
}
