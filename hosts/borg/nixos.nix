{ lib, homelab, ... }:
{

  networking.networkmanager.enable = lib.mkForce false;

  # Add hosts's ssh keys for borg's backups
  users.users.${homelab.username}.openssh.authorizedKeys.keyFiles = map (
    host: ../${host}/keys/ssh_host_rsa_key.pub) (builtins.attrNames homelab.hosts);

}
