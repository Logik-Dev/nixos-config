{
  flake.modules.nixos.hardening = {
    security.sudo.wheelNeedsPassword = false;
    users.users.root.hashedPassword = "!";
  };

  flake.modules.darwin.common = {
    security.pam.services.sudo_local.touchIdAuth = true;
  };
}
