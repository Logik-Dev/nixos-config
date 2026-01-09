let
  flake.modules.nixos = { inherit hyper; };

  hyper = {
    systemd.network.links."10-management" = {
      matchConfig.MACAddress = "fc:34:97:10:ca:04";
      linkConfig.Name = "management";
    };

    systemd.network.links."10-vms" = {
      matchConfig.MACAddress = "98:b7:85:00:8f:f2";
      linkConfig.Name = "vms";
    };

    networking = {
      defaultGateway = "192.168.10.1"; # default route

      vlans = {
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

      bridges.br-iot = {
        interfaces = [ "vlan21" ];
      };

      interfaces = {
        vlan21.useDHCP = false;
        vlan100.useDHCP = false;
        vlan200.useDHCP = false;

        management = {
          useDHCP = false;
          ipv4.addresses = [
            {
              address = "192.168.10.100";
              prefixLength = 24;
            }
          ];
        };

        br-iot = {
          useDHCP = false;
          ipv4.addresses = [
            {
              address = "192.168.21.241";
              prefixLength = 24;
            }
          ];
        };
      };
    };

  };
in
{
  inherit flake;
}
