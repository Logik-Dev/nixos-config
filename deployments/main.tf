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
  username = nonsensitive(local.username)
}

module "container_image" {
  source   = "./images"
  username = local.username
}

module "dns_instance" {
  source         = "./instance"
  hostname       = "dns"
  image          = one(module.container_image.aliases)
  hwaddr         = local.machines["dns"].hwaddr
  root_disk_pool = module.storage_pools.btrfs_pool
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




