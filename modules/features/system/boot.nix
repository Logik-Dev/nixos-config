{
  flake.modules.nixos.common = {
    boot.loader.systemd-boot = {
      enable = true;
      configurationLimit = 5;
      memtest86.enable = true;
    };
    boot.loader.efi.canTouchEfiVariables = true;
    hardware.enableRedistributableFirmware = true;

  };
}
