{ hosts, username, ... }:
{

  # Add machines ssh keys for borg's backups
  users.users.${username}.openssh.authorizedKeys.keyFiles = map (
    host: ../${host}/keys/ssh_host_rsa_key.pub) (builtins.attrNames hosts);

}
