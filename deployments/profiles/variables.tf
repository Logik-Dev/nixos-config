variable "username" {
  description = "Admin username"
  type        = string
}

variable "storage_pools" {
  description = "Storage pools and volumes"
  type = object({
    lvm_pool              = string
    btrfs_pool            = string
    nextcloud_data_volume = string
  })
}
