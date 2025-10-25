{ inputs, ... }:
let
  inherit (inputs.self.meta.owner) username;

  flake.modules.nixos.libvirt.imports = [
    libvirt
    vlans
    bridges
    interfaces
  ];

  libvirt = {
    users.users."${username}".extraGroups = [ "libvirtd" ];
    virtualisation.libvirtd = {
      enable = true;
    };
  };

  vlans = {
    networking.vlans = {
      vlan21 = {
        id = 21;
        interface = "vms";
      };
      vlan100 = {
        id = 100;
        interface = "vms";
      };
      vlan200 = {
        id = 200;
        interface = "vms";
      };
    };
  };

  bridges = {
    networking.bridges = {
      vlan21-iot = {
        interfaces = [ "vlan21" ];
      };
      vlan100-talos = {
        interfaces = [ "vlan100" ];
      };
      vlan200-gateway = {
        interfaces = [ "vlan200" ];
      };
    };
  };

  interfaces = {
    networking.interfaces = {
      vlan21-iot.useDHCP = false;
      vlan100-talos.useDHCP = false;
      vlan200-gateway.useDHCP = false;
    };
  };
in
{
  inherit flake;
}
