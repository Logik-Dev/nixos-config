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

output "lvm_pool" {
  value = incus_storage_pool.lvm_pool.name
}

output "btrfs_pool" {
  value = incus_storage_pool.btrfs_pool.name

}
