{ inputs, ... }:
let
  flake.lib.mk-home = {
    inherit userOnHost logikdevOnHost;
  };

  mkConfig =
    user: host: extraModules:
    let
      isDarwin = inputs.self.darwinConfigurations ? ${host};
      isNixOS = inputs.self.nixosConfigurations ? ${host};

      systemConfig =
        if isDarwin then
          inputs.self.darwinConfigurations.${host}
        else if isNixOS then
          inputs.self.nixosConfigurations.${host}
        else
          throw "Host ${host} not found in nixosConfigurations or darwinConfigurations";

      modules = (mkDefaultHomeModules user isDarwin) ++ extraModules;

      config = inputs.home-manager.lib.homeManagerConfiguration {
        inherit modules;
        pkgs = systemConfig.pkgs;
      };
    in
    {
      inherit config modules;
    };

  mkDefaultHomeModules = user: isDarwin: [
    inputs.self.modules.homeManager.common
    inputs.self.modules.homeManager.${user}
    {
      home.username = user;
      home.homeDirectory = if isDarwin then "/Users/${user}" else "/home/${user}";
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
