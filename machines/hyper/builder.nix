{
  ...
}:
{

  users.groups.nix-builder = { };

  # create a user for remote builds
  users.users.nix-builder = {
    isNormalUser = true;
    group = "nix-builder";
    createHome = false;
    openssh.authorizedKeys.keyFiles = [ ../common/keys/nix-builder-key.pub ];
  };

  nix.settings.trusted-users = [ "nix-builder" ];

}
