let
  flake.modules.nixos = { inherit hyper; };

  hyper =
    { config, ... }:
    {
      systemd.network.links."10-management" = {
        matchConfig.MACAddress = config.constants.hosts.hyper.mac.management;
        linkConfig.Name = "management";
      };

      systemd.network.links."10-vms" = {
        matchConfig.MACAddress = config.constants.hosts.hyper.mac.vms;
        linkConfig.Name = "vms";
      };

      networking = {
        defaultGateway = config.constants.hosts.hyper.gateway; # default route

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
                address = config.constants.hosts.hyper.lanIp;
                prefixLength = config.constants.hosts.hyper.prefixLength;
              }
            ];
          };

          br-iot = {
            useDHCP = false;
            ipv4.addresses = [
              {
                address = config.constants.hosts.hyper.iot.ip;
                prefixLength = config.constants.hosts.hyper.prefixLength;
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
