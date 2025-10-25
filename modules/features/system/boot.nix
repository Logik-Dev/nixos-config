{
  flake.modules.nixos.common =
    { pkgs, ... }:
    {
      boot.loader.systemd-boot = {
        enable = true;

        configurationLimit = 5;
      };
      boot.loader.efi.canTouchEfiVariables = true;
      boot.kernelPackages = pkgs.linuxPackages_latest;
      hardware.enableRedistributableFirmware = true;
    };
}
