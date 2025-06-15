terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "0.3.1"
    }
  }
}

# lvm pool
resource "incus_storage_pool" "lvm_pool" {
  name   = "lvm_pool"
  driver = "lvm"
  config = {
    source              = "vg_ultra"
    "lvm.thinpool_name" = "pool"
  }
  lifecycle {
    prevent_destroy = true
  }
}

# btrfs pool
resource "incus_storage_pool" "btrfs_pool" {
  name   = "btrfs_pool"
  driver = "btrfs"
  config = {
    source = "/mnt/local/pool"
  }
  lifecycle {
    prevent_destroy = true
  }
}

# nextcloud data volume
resource "incus_storage_volume" "nextcloud_data" {
  name         = "nextcloud_data"
  pool         = incus_storage_pool.lvm_pool.name
  content_type = "filesystem"
  config = {
    size = "1TiB"
  }

}

output "lvm_pool" {
  value = incus_storage_pool.lvm_pool.name
}

output "btrfs_pool" {
  value = incus_storage_pool.btrfs_pool.name
}

output "nextcloud_data_volume" {
  value = incus_storage_volume.nextcloud_data.name
}
