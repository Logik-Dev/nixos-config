{ lib, pkgs, ... }:
let
  mkProfile = name: description: devices: { inherit name devices description; };

  mkVlanProfile =
    vlan: description:
    mkProfile "vlan${toString vlan}" description {
      eth0 = {
        inherit vlan;
        name = "eth0";
        type = "nic";
        nictype = "macvlan";
        parent = "enp4s0";
      };
    };
  sizes = [
    "30GiB"
    "60GiB"
    "100GiB"
    "500GiB"
  ];
  mkStorageProfile =
    pool: size:
    mkProfile "${pool}-${size}" "" {
      root = {
        inherit pool size;
        path = "/";
        type = "disk";
      };
    };

  mkStorageProfiles = pool: map (size: mkStorageProfile pool size) sizes;

  mountOptions = builtins.concatStringsSep "," [
    "noatime"
    "compress=zstd"
    "ssd"
    "space_cache=v2"
    "commit=15"
  ];

  mkBtrfsPool = name: source: {
    inherit name;
    driver = "btrfs";
    config = {
      inherit source;
      "btrfs.mount_options" = mountOptions;
    };
  };
in
{
  virtualisation.libvirtd.enable = true;
  networking.nftables.enable = true;
  networking.useNetworkd = true;
  networking.networkmanager.enable = lib.mkForce false;
  environment.systemPackages = with pkgs; [ btrfs-progs ];
  virtualisation.incus = {
    enable = true;
    ui.enable = true;
    preseed = {
      config = {
        "core.https_address" = ":8443";
      };

      profiles = [
        (mkVlanProfile 11 "Containers network")
        (mkVlanProfile 21 "IoT network")
      ] ++ mkStorageProfiles "local" ++ mkStorageProfiles "ultra";

      storage_pools = [
        (mkBtrfsPool "local" "/pools/local")
        (mkBtrfsPool "ultra" "/pools/ultra")
      ];
    };
  };

  networking.firewall.allowedTCPPorts = [ 8443 ];

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
