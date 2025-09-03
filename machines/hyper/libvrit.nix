{ pkgs, ... }:
{
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      ovmf.enable = true;
      ovmf.packages = [ pkgs.OVMFFull.fd ];
    };
    extraConfig = ''
      # Augmenter les limites pour éviter les timeouts Terraform
      max_client_requests = 20
      max_queued_clients = 50
      keepalive_interval = 5
      keepalive_count = 5

      # Optimisations performance
      log_level = 2
      log_filters = "1:qemu 1:libvirt 4:object 4:json 4:event 1:util"

    '';
  };
  networking = {
    # Vlans
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

    # Bridges
    bridges = {
      vlan21-iot = {
        interfaces = [
          "vlan21"
        ];
      };
      vlan100-talos = {
        interfaces = [
          "vlan100"
        ];
      };
      vlan200-gateway = {
        interfaces = [ "vlan200" ];
      };
    };

    interfaces = {
      vlan21-iot.useDHCP = false;
      vlan100-talos.useDHCP = false;
      vlan200-gateway.useDHCP = false;
    };
  };
}
