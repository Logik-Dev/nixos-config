
module "incus_instance" {
  source         = "./incus_instance"
  name           = var.hostname
  type           = var.type
  image          = var.images[var.type]
  profiles       = [for x in var.profiles : var.incus_profiles[x]]
  root_disk_pool = var.storage_pools[var.type == "container" ? "btrfs_pool" : "lvm_pool"]
  vlan           = var.vlan
  hwaddr         = var.hwaddr
  memory         = var.memory
  size           = var.size
  cpus           = var.cpus
}

module "nixos_rebuild" {
  source = "../nixos_rebuild"
  ipv4   = module.incus_instance.ipv4
  special_args = {
    hostname = var.hostname
    username = var.username
    email    = var.email
    domain   = var.domain
  }
}
