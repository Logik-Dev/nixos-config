{ inputs, ... }:
let
  host = (
    inputs.self.lib.mk-host {
      host = "sonicmaster";
      osClass = "nixos";
      useGlobalPkgs = true;
      modules = with inputs.self.modules.homeManager; [
        browsers
        desktop
        dev
        gpg
        keyboard
        passwords
        virtualization
      ];
    }
  );

  flake.homeConfigurations."logikdev@sonicmaster" = host.homeConfig.config;
  flake.modules.nixos.sonicmaster.imports = [ host.homeImport ];
in
{
  inherit flake;
}
