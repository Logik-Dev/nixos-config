{
  self,
  makeMachine,
  inputs,
  flakeOverlays,
  lib,
  ...
}:
{
  flake = {
    nixosConfigurations.sonicmaster = makeMachine {
      system = "x86_64-linux";
      user = "logikdev";
      nixosModules = with self.nixosModules; [
        ./hardware-configuration.nix
        ./nixos.nix
        minimal
        desktop
      ];
      hmModules = with self.hmModules; [
        ./hm.nix
        minimal
        desktop
      ];
    };

    homeConfigurations."logikdev@sonicmaster" = inputs.home-manager.lib.homeManagerConfiguration {
      modules =
        (with self.hmModules; [
          minimal
          desktop
        ])
        ++ [ ./hm.nix ];
      pkgs = import inputs.nixpkgs rec {
        system = "x86_64-linux";
        overlays = flakeOverlays system;

      };
    };
  };
}
