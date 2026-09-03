{
  inputs,
  lib,
  ...
}:
let
  flake.modules.nixos.sonicmaster.imports =
    (with inputs.self.modules.nixos; [
      audio
      common
      gnome
      kvm-intel
      logikdev
      neovim
      network
      tailscale
      yubikey
    ])
    ++ [
      # host-specific tailscale config
      {
        services.tailscale = {
          useRoutingFeatures = "client";
          extraUpFlags = [ "--accept-routes" ];
        };
      }
      # virt-manager
      {
        programs.virt-manager.enable = true;
      }
      # Managed locally only: no remote SSH access (sshd was enabled by
      # nixos.common but no authorizedKeys were ever declared).
      {
        services.openssh.enable = false;
      }
    ];

  network = {
    networking.networkmanager.enable = true;
    networking.useDHCP = lib.mkDefault true;
  };

in
{
  inherit flake;
}
