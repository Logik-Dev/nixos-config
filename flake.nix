{
  description = "NixOS Configuration";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:nixos/nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    flake-root.url = "github:srid/flake-root";

    git-hooks-nix = {
    	url = "github:cachix/git-hooks.nix";
			inputs.nixpkgs.follows = "nixpkgs";
		};

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    "blink.compat" = {
      url = "github:saghen/blink.compat";
      flake = false;
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { self, ... }:
      {

        systems = [ "x86_64-linux" ];

        debug = true;

        imports = [
          ./hosts
          ./nixvim/pkg.nix
          inputs.treefmt-nix.flakeModule
          inputs.flake-root.flakeModule
					inputs.git-hooks-nix.flakeModule
        ];

        perSystem =
          {
            config,
            self',
            inputs',
            pkgs,
            system,
            ...
          }:
          {
            _module.args = {
              pkgs = import inputs.nixpkgs { inherit system; };
            };

            formatter = config.treefmt.build.wrapper;

            treefmt.config = {
              inherit (config.flake-root) projectRootFile;
              programs = {
                nixfmt-rfc-style.enable = true;
                statix.enable = true;
              };
            };
						
						pre-commit.settings.hooks.nixfmt-rfc-style.enable = true;

						devShells.default = pkgs.mkShell {
							            shellHook = ''
              ${config.pre-commit.installationScript}
              echo 1>&2 "Welcome to the development shell!"
            '';
						};
          };

        flake = {
          nixosModules = {
            minimal = import ./minimal/nixos.nix { };
          };

          hmModules = {
            minimal = import ./minimal/hm.nix {
              inherit inputs;
              flake = self;
            };
            desktop = import ./desktop/hm.nix;
          };
        };
      }
    );
}
