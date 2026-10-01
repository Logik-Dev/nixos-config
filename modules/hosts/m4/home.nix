{ inputs, ... }:
let
  host = inputs.self.lib.mk-host {
    host = "m4";
    useGlobalPkgs = true;
    useUserPackages = true;
    modules = with inputs.self.modules.homeManager; [
      ai-agent
      desktop
      dev
      multi-agent-plan
      musique
    ];
  };

  flake.homeConfigurations."logikdev@m4" = host.homeConfig.config;
  flake.modules.darwin.m4.imports = [ host.homeImport ];
in
{
  inherit flake;
}
