{ inputs, ... }:
let
  inherit (inputs.self.meta.owner) email fullname sshKey;

  jjStarship =
    { ... }:
    {
      nixpkgs.overlays = [ inputs.jj-starship.overlays.default ];
    };

in

{
  flake.modules = {
    # Avoid warnings when using home-manager.useGlobalPkgs
    nixos.common.imports = [ jjStarship ];
    darwin.common.imports = [ jjStarship ];

    homeManager.jj = {
      programs.jujutsu = {
        enable = true;
        settings = {
          user = {
            inherit email;
            name = fullname;
          };
          inherit email;
          signing.behavior = "own";
          signing.backend = "ssh";
          signing.key = sshKey;

        };
      };

      programs.starship.settings = {
        custom.jj = {
          when = "jj-starship detect";
          shell = [ "jj-starship" ];
          format = "$output ";
        };
      };
    };
  };
}
