{
  flake.modules.nixos.common = {
    boot.loader.systemd-boot = {
      enable = true;
      configurationLimit = 5;
    };
    boot.loader.efi.canTouchEfiVariables = true;
    hardware.enableRedistributableFirmware = true;

  };
}
