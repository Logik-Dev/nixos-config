{ inputs, ... }:
let

  flake.lib.mk-home = {
    inherit userOnHost logikdevOnHost;
  };

  mkConfig =
    user: host: extraModules:
    let
      modules = (mkDefaultHomeModules user) ++ extraModules;

      config = inputs.home-manager.lib.homeManagerConfiguration {
        inherit modules;
        pkgs = inputs.self.nixosConfigurations.${host}.pkgs;
        extraSpecialArgs.osConfig = [ inputs.self.nixosConfigurations.${host}.config ];
      };
    in
    {
      inherit config modules;
    };

  mkDefaultHomeModules = user: [
    inputs.self.modules.homeManager.common
    {
      home.username = user;
      home.homeDirectory = "/home/${user}";
      home.stateVersion = "25.05";
    }
  ];

  userOnHost =
    user: host: modules:
    mkConfig user host modules;

  logikdevOnHost = host: modules: userOnHost "logikdev" host modules;

in
{
  inherit flake;
}
