{
  inputs,
  lib,
  ...
}:
let
  flake.modules.nixos.sonicmaster.imports = with inputs.self.modules.nixos; [
    agenix
    audio
    common
    ddns
    gnome
    #kde-desktop
    kvm-intel
    network
    yubikey
  ];

  network = {
    networking.networkmanager.enable = true;
    networking.useDHCP = lib.mkDefault true;
  };

in
{
  inherit flake;
}
