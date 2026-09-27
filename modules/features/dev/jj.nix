{ inputs, ... }:
let

  jjStarship = _: {
    nixpkgs.overlays = [ inputs.jj-starship.overlays.default ];
  };

in

{
  flake.modules = {
    # Avoid warnings when using home-manager.useGlobalPkgs
    nixos.common.imports = [ jjStarship ];
    darwin.common.imports = [ jjStarship ];
    homeManager.jj =
      { config, pkgs, ... }:
      let
        key =
          if pkgs.stdenv.isDarwin then
            config.constants.users.logikdev.sshKeyMac
          else
            config.constants.users.logikdev.sshKey;
      in
      {
        programs.jujutsu = {
          enable = true;
          settings = {
            user = {
              email = config.constants.users.logikdev.email;
              name = config.constants.users.logikdev.fullname;
            };
            signing.behavior = "own";
            signing.backend = "ssh";
            signing.key = key;

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
