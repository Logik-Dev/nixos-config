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

  # mergerfs dir
  device {
    name = "borg"
    type = "disk"
    properties = {
      source = "/mnt/storage/borg"
      path   = "/home/${var.username}/borg/storage"
    }
  }

  # usb backups
  device {
    name = "usb"
    type = "usb"
    properties = {
      busnum    = 2
      devnum    = 5
      productid = "2620"
      vendorid  = "1058"
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

resource "incus_profile" "nextcloud_import" {
  name        = "nextcloud_import"
  description = "Folder to import nextcloud to immich"
  device {
    name = "import"
    type = "disk"
    properties = {
      source = "/mnt/backups/nextcloud-backup"
      path   = "/mnt/import"
    }
  }
}

# nextcloud data
resource "incus_profile" "nextcloud_data" {
  name        = "nextcloud_data"
  description = "Nextcloud data directory"
  device {
    type = "disk"
    name = "nextcloud_data"
    properties = {
      pool   = var.storage_pools.lvm_pool
      source = var.storage_pools.nextcloud_data_volume
      path   = "/mnt/photos"
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

output "nextcloud_data" {
  value = incus_profile.nextcloud_data.name
}

output "nextcloud_import" {
  value = incus_profile.nextcloud_import.name
}
