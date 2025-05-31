terraform {
  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "1.2.0"
    }
    incus = {
      source  = "lxc/incus"
      version = "0.3.1"
    }
  }
}

provider "sops" {}

# global vars passed as specialArgs to nix
data "sops_file" "globals" {
  source_file = "./secrets.yaml"
}

locals {
  machines = jsondecode(file("./machines.json"))
  username = data.sops_file.globals.data["username"]
  email    = data.sops_file.globals.data["email"]
  domain   = data.sops_file.globals.data["domain"]
}

module "storage_pools" {
  source = "./storage"
}

module "profiles" {
  source   = "./profiles"
  username = local.username
}

module "images" {
  source   = "./images"
  username = local.username
}

module "instances" {
  for_each       = { for k, v in local.machines : k => v if v.platform != "bare-metal" }
  source         = "./instance"
  hostname       = each.key
  type           = local.machines[each.key].platform
  images         = module.images
  storage_pools  = module.storage_pools
  incus_profiles = module.profiles
  profiles       = local.machines[each.key].profiles
  cpus           = local.machines[each.key].cpus
  memory         = local.machines[each.key].memory
  hwaddr         = local.machines[each.key].hwaddr
  vlan           = local.machines[each.key].vlan
  size           = local.machines[each.key].size
  username       = nonsensitive(local.username)
  email          = nonsensitive(local.email)
  domain         = nonsensitive(local.domain)
}
/*
module "dns_instance" {
  source         = "./instance"
  hostname       = "dns"
  image          = module.images.container
  hwaddr         = local.machines["dns"].hwaddr
  root_disk_pool = module.storage_pools.btrfs_pool
  profiles       = [for x in local.machines["dns"].profiles : module.profiles[x]]
}

module "dns_rebuild" {
  source = "./nixos_rebuild"
  special_args = {
    hostname = "dns"
    username = nonsensitive(local.username)
    email    = nonsensitive(local.email)
    domain   = nonsensitive(local.domain)
  }
  ipv4 = module.dns_instance.ipv4
}
*/



