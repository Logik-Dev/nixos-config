{ inputs, lib, ... }:
let
  flake.lib.mk-host =
    {
      host,
      modules,
      useGlobalPkgs ? false,
      useUserPackages ? false,
    }:
    let
      inherit (inputs.self.lib.mk-home) logikdevOnHost;

      homeConfig = logikdevOnHost host modules;

      homeImport = _: {
        home-manager.users.logikdev.imports = homeConfig.modules;
        home-manager.useGlobalPkgs = lib.mkDefault useGlobalPkgs;
        home-manager.useUserPackages = lib.mkDefault useUserPackages;
      };
    in
    {
      inherit homeConfig homeImport;
    };
in
{
  inherit flake;
}
