{ inputs, ... }:
let
  inherit (inputs.self.meta.owner) username;

in
{
  flake.modules.nixos.hyper = {

    # home assistant
    services.reverse-proxy.vhosts.hass = {
      port = 8123;
      host = "192.168.21.181";
      enableWebsockets = true;
    };

    users.users."${username}".extraGroups = [ "libvirtd" ];

    virtualisation.libvirtd.enable = true;
  };

  flake.modules.nixos.sonicmaster = {
    programs.virt-manager.enable = true;
  };
}
