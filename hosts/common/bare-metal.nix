{ ... }:
{
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 10;
  };

  services.resolved = {
    enable = true;
    dnssec = "false";
  };
  boot.loader.efi.canTouchEfiVariables = true;
}
