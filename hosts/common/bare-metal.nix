{ ... }:
{
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 10;
  };

  services.resolved = {
    enable = true;
    dnssec = "true";
  };

  boot.loader.efi.canTouchEfiVariables = true;
}
