{
  flake.modules.nixos.no-root-password = {
    security.sudo.wheelNeedsPassword = false;
  };
  flake.modules.darwin.common = {
    security.pam.services.sudo_local.touchIdAuth = true;
  };
}
