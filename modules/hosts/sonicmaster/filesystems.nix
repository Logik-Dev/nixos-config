{
  flake.modules.nixos.sonicmaster = {
    fileSystems."/" = {
      device = "/dev/disk/by-uuid/80400ae1-655d-45e6-935a-9b14af3f0ed7";
      fsType = "ext4";
    };

    fileSystems."/boot" = {
      device = "/dev/disk/by-uuid/8048-6F3E";
      fsType = "vfat";
      options = [
        "fmask=0077"
        "dmask=0077"
      ];
    };

    swapDevices = [ ];
  };
}
