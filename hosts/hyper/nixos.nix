{ inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.default
    #./hardware-configuration.nix
    inputs.nixos-facter-modules.nixosModules.facter
    { config.facter.reportPath = ./facter.json; }
    ./disko.nix
    ../common/bare-metal.nix
  ];
}
