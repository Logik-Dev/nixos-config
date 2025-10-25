{ inputs, ... }:
let
  inherit (inputs.self.lib.mk-home) logikdevOnHost;

  flake.homeConfigurations."logikdev@hyper" = logikdevConfigWithModules.config;

  flake.modules.nixos.hyper.imports = [ home ];

  logikdevModules = with inputs.self.modules.homeManager; [
    dev
  ];

  logikdevConfigWithModules = logikdevOnHost "hyper" logikdevModules;

  # Home manager in nixos
  home = {
    home-manager.users.logikdev.imports = logikdevConfigWithModules.modules;
  };

in
{
  inherit flake;
}
