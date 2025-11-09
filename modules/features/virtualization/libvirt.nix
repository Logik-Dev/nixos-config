{ inputs, ... }:
let
  inherit (inputs.self.meta.owner) username;

  flake.modules.nixos.libvirt.imports = [
    libvirt
  ];

  libvirt = {
    users.users."${username}".extraGroups = [ "libvirtd" ];
    virtualisation.libvirtd = {
      enable = true;
    };
  };

in
{
  inherit flake;
}
