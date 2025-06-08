{ hosts, username, ... }:

{

  # Add machines ssh keys for borg's backups
  users.users.${username}.openssh.authorizedKeys.keyFiles = map (
    host: ../${host}/keys/ssh_host_rsa_key.pub) (builtins.attrNames hosts);

  systemd.mounts = [
    {
      what = "/dev/disk/by-uuid/49fe812c-672a-4018-935c-e10c1827f0c4";
      where = "/home/${username}/borg/usb";
      type = "btrfs";
      options = "nofail,noatime,compress=zstd,space_cache=v2";
    }
  ];

  systemd.automounts = [
    {
      where = "/home/${username}/borg/usb";
      wantedBy = [ "multi-user.target" ];
      automountConfig = {
        TimeoutIdleSec = "300"; # unmount after 5 minutes
      };
    }
  ];
}
