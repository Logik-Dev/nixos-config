{ inputs, ... }:
let
  inherit (inputs.self.meta.owner) username;

in
{
  flake.modules.nixos.hyper = {
    networking.bridges.br-iot.interfaces = [ "vlan21" ];

    users.users."${username}".extraGroups = [ "libvirtd" ];

    virtualisation.libvirtd.enable = true;
  };

  flake.modules.nixos.sonicmaster = {
    programs.virt-manager.enable = true;
  };
}
