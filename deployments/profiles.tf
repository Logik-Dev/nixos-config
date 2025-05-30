resource "incus_profile" "default" {
  description = "Default Incus profile"
  name = "default"

  device {
    name = "root"
    type = "disk"
    properties = {
      pool = "btrfs-pool"
      path = "/"
    }
  }

  device {
    name = "eth0"
    type = "nic"
    properties = {
      nictype = "macvlan"
      parent  = "enp4s0"
      vlan    = 11
    }
  }
}
