{
  flake.modules.nixos.hyper =
    { config, ... }:
    {
      traefik.services.hass = {
        port = 8123;
        host = "192.168.21.181";
        category = "Maison";
        icon = "di:home-assistant";
        title = "Home Assistant";
      };
      users.users.${config.constants.users.logikdev.username}.extraGroups = [ "libvirtd" ];
      virtualisation.libvirtd.enable = true;
    };
}
