{ homelab, lib, ... }:
{
  services.adguardhome = {
    enable = true;
    openFirewall = true;
    mutableSettings = false;
    settings = {
      dns =
        {
        };
    };
  };
}
