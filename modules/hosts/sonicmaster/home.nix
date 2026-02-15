{ inputs, ... }:
let
  inherit (inputs.self.lib.mk-home) logikdevOnHost;

  flake.homeConfigurations."logikdev@sonicmaster" = logikdevConfigWithModules.config;

  flake.modules.nixos.sonicmaster.imports = [ home ];

  logikdevModules = with inputs.self.modules.homeManager; [
    browsers
    desktop
    dev
    gpg
    management
    passwords
    virtualization
  ];

  logikdevConfigWithModules = logikdevOnHost "sonicmaster" logikdevModules;

  # Home manager in nixos
  home = {
    home-manager.users.logikdev.imports = logikdevConfigWithModules.modules;
  };

in
{
  inherit flake;
}
