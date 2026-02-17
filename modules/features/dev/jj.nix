{ inputs, ... }:
let

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
    homeManager.jj =
      { config, ... }:
      {
        programs.jujutsu = {
          enable = true;
          settings = {
            user = {
              email = config.constants.users.logikdev.email;
              name = config.constants.users.logikdev.fullname;
            };
            email = config.constants.users.logikdev.email;
            signing.behavior = "own";
            signing.backend = "ssh";
            signing.key = config.constants.users.logikdev.sshKey;

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
