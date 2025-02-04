{ lib, pkgs, ... }:
{

  services.xserver.enable = true;

  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  services.gnome.gnome-keyring.enable = lib.mkForce false;

  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  virtualisation.libvirtd.enable = true;
  networking.nftables.enable = true;
  virtualisation.incus = {
    enable = true;
    package = pkgs.incus;
    agent.enable = true;
    ui.enable = true;
    #    preseed = { };
    preseed = {
      networks = [
        {
          config = {
            "ipv4.address" = "auto";
            "ipv6.address" = "none";
            #"ipv4.nat" = "true";
          };
          name = "incusbr0";
          type = "bridge";
        }
      ];
      profiles = [
        {
          devices = {
            eth0 = {
              name = "eth0";
              type = "nic";
              nictype = "bridged";
              parent = "incusbr0";
            };
            root = {
              path = "/";
              pool = "default";
              size = "35GiB";
              type = "disk";
            };
          };
          name = "default";
        }
      ];
      storage_pools = [
        {
          config = {
            source = "/var/lib/incus/storage-pools/default";
          };
          driver = "dir";
          name = "default";
        }
      ];
    };
  };
  networking.firewall.interfaces.incusbr0.allowedTCPPorts = [
    53
    67
  ];
  networking.firewall.interfaces.incusbr0.allowedUDPPorts = [
    53
    67
  ];

  programs.virt-manager.enable = true;
  users.users.logikdev.extraGroups = [
    "libvirtd"
    "incus-admin"
  ];

}
