{ modulesPath, lib, ... }:
{
  imports = [
    # Include the default lxd configuration.
    # "${modulesPath}/virtualisation/lxc-container.nix"
  ];

  networking.networkmanager.enable = lib.mkForce false;

}
