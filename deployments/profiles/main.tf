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
      source = "/mnt/storage/borg"
      path   = "/home/${var.username}/borg"
    }
  }
}

# intel_gpu
resource "incus_profile" "intel_gpu" {
  description = "Intel UHD Graphics"
  name        = "intel_gpu"
  device {
    name = "intel_gpu"
    type = "gpu"
    properties = {
      pci = "0000:00:02.0"
    }
  }
}

# medias_shares
resource "incus_profile" "medias_shares" {
  name        = "medias_shares"
  description = "Medias Shares"
  device {
    name = "medias"
    type = "disk"
    properties = {
      source = "/mnt/storage/medias"
      path   = "/medias"
    }
  }
}

output "backup_folders" {
  value = incus_profile.backup_folders.name
}

output "intel_gpu" {
  value = incus_profile.intel_gpu.name
}

output "medias_shares" {
  value = incus_profile.medias_shares.name
}
