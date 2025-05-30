resource "incus_profile" "default" {
  description = "Default Incus profile"
  name        = "default"

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

resource "incus_profile" "backup-folders" {
  description = "Shared backup folders"
  name        = "backup-folders"

  device {
    name = "borg"
    type = "disk"
    properties = {
      shift  = true
      source = "/mnt/storage/borg"
      path   = format("/home/%s/borg", nonsensitive(data.sops_file.nix_globals.data["username"]))
    }
  }
}
