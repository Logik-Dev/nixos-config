{
  flake.modules.nixos.hardening = {
    # Passwordless sudo for wheel: kept on purpose. Remote deploys run
    # `nh os switch` over a non-interactive SSH session, and requiring a
    # password would only protect against SSH-key compromise — which is moot
    # here since a NOPASSWD deploy path (or the key itself) is already
    # root-equivalent for a single-admin host.
    security.sudo.wheelNeedsPassword = false;
    users.users.root.hashedPassword = "!";
  };

  flake.modules.darwin.common = {
    security.pam.services.sudo_local.touchIdAuth = true;
  };
}
