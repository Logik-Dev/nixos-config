{
  self,
  inputs,
  flakeOverlays,
  ...
}:
{
  _module.args = {
    flakeOverlays = system: [
      (final: prev: self.packages.${system}) # add toplevel flake packages (nixvim...)
    ];
    makeMachine =
      {
        system,
        user,
        nixosModules,
        hmModules,
      }:
      inputs.nixpkgs.lib.nixosSystem {
        inherit system;
        modules = nixosModules ++ [
          inputs.home-manager.nixosModules.home-manager
          {
            nixpkgs = {
              overlays = flakeOverlays system;
            };
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.${user} = {
                imports = hmModules;
              };
              extraSpecialArgs = {
                flake = self;
              };
            };
          }
        ];
      };
  };

  imports = [ ./sonicmaster ];
}
