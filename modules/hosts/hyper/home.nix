{ inputs, ... }:
let
  host = inputs.self.lib.mk-host {
    host = "hyper";
    modules = with inputs.self.modules.homeManager; [
      jj
      dev
    ];
  };

  flake.homeConfigurations."logikdev@hyper" = host.homeConfig.config;
  flake.modules.nixos.hyper.imports = [ host.homeImport ];
in
{
  inherit flake;
}
