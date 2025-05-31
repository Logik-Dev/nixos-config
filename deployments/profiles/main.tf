terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "0.3.1"
    }
  }
}

# borg backup-folders
resource "incus_profile" "backup_folders" {
  description = "Shared backup folders"
  name        = "backup_folders"

  device {
    name = "borg"
    type = "disk"
    properties = {
      shift  = true
      source = "/mnt/data1/borg" # Can't get shift working on mergerfs (idmap problem)
      path   = "/home/${var.username}/borg"
    }
  }
}

output "backup_folders" {
  value = incus_profile.backup_folders.name
}
