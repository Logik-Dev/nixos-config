{ inputs, ... }:
let
  inherit (inputs.self.lib.mk-home) logikdevOnHost;

  flake.homeConfigurations."logikdev@m4" = logikdevConfigWithModules.config;

  flake.modules.darwin.m4.imports = [ home ];

  logikdevModules = with inputs.self.modules.homeManager; [
    common
    desktop
    dev
    #management
    #passwords
    #virtualization
  ];

  logikdevConfigWithModules = logikdevOnHost "m4" logikdevModules;

  # Home manager in darwin
  home = {
    home-manager.users.logikdev.imports = logikdevConfigWithModules.modules;
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
  };
in
{
  inherit flake;
}
