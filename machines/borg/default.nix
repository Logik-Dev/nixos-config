{ hosts, username, ... }:
{

  # Add machines ssh keys for borg's backups
  users.users.${username}.openssh.authorizedKeys.keyFiles = map (
    host: ../${host}/keys/ssh_host_rsa_key.pub) (builtins.attrNames hosts);

  fileSystems."usb" = {
    device = "/dev/sdb";
    fsType = "btrfs";
    mountPoint = "/home/${username}/borg/usb";
    options = [
      "nofail" # dont block system if failed
      "noatime"
      "compress=zstd"
      "space_cache=v2"
      "commit=15"
    ];
  };
}
