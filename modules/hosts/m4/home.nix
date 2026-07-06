{ inputs, ... }:
let
  host = (
    inputs.self.lib.mk-host {
      host = "m4";
      osClass = "darwin";
      useGlobalPkgs = true;
      useUserPackages = true;
      modules = with inputs.self.modules.homeManager; [
        ai-agent
        desktop
        dev
        #passwords
        #virtualization
      ];
    }
  );

  flake.homeConfigurations."logikdev@m4" = host.homeConfig.config;
  flake.modules.darwin.m4.imports = [ host.homeImport ];
in
{
  inherit flake;
}
