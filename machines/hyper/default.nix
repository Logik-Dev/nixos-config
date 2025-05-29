{
  inputs,
  ...
}:
{
  imports = [
    inputs.disko.nixosModules.default
    inputs.nixos-facter-modules.nixosModules.facter
    { config.facter.reportPath = ./facter.json; }
    ./disko.nix
    ./incus.nix
    ./mergerfs.nix
    ./snapraid.nix
  ];

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 20;
  };

}
