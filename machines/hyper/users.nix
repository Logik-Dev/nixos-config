{
  username,
  lib,
  config,
  ...
}:
{

  sops.secrets.password.neededForUsers = true;

  # Users configuration
  users.groups.media.gid = lib.mkForce 991;
  security.sudo.wheelNeedsPassword = false;
  users.users."${username}" = {
    extraGroups = [
      "wheel"
      "networkmanager"
      "libvirtd"
    ];
    isNormalUser = true;
    hashedPasswordFile = config.sops.secrets.password.path;
    openssh.authorizedKeys.keyFiles = [
      ./keys/yubikey.pub
    ];
  };
}
