{
  flake.modules.nixos.no-root-password = {
    security.sudo.wheelNeedsPassword = false;
  };
}
