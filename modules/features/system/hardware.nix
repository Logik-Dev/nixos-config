{ inputs, ... }:
{
  flake.modules.nixos.common =
    { config, lib, ... }:
    let
      facterPath = inputs.self + "/modules/hosts/${config.networking.hostName}/facter.json";
    in
    {
      imports = [ inputs.nixos-facter-modules.nixosModules.facter ];

      # A host without a facter report simply gets the tool's default empty
      # report instead of breaking evaluation (facter.reportPath defaults to null).
      facter.reportPath = lib.mkIf (builtins.pathExists facterPath) facterPath;
    };
}
