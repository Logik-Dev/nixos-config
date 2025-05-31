terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "0.3.1"
    }
  }
}

# borg backup-folders
resource "incus_profile" "backup-folders" {
  description = "Shared backup folders"
  name        = "backup-folders"

  device {
    name = "borg"
    type = "disk"
    properties = {
      #shift  = true
      source = "/mnt/storage/borg"
      path   = "/home/${var.username}/borg"
    }
  }
}
