terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "0.3.1"
    }
  }
}

locals {
  nixos_container_config_path = "../.#nixosConfigurations.container.config.system.build"
  nixos_vm_config_path        = "../.#nixosConfigurations.virtual-machine.config.system.build"
}

# nix build container image
module "nix_build_container_image" {
  source    = "github.com/nix-community/nixos-anywhere//terraform/nix-build"
  attribute = "${local.nixos_container_config_path}.squashfs"
  special_args = {
    hostname = var.hostname
    username = var.username
  }
}

# nix build vm image
module "nix_build_vm_image" {
  source    = "github.com/nix-community/nixos-anywhere//terraform/nix-build"
  attribute = "${local.nixos_vm_config_path}.qemuImage"
  special_args = {
    hostname = var.hostname
    username = var.username
  }
}

# nix build container metadata
module "nix_build_container_metadata" {
  source    = "github.com/nix-community/nixos-anywhere//terraform/nix-build"
  attribute = "${local.nixos_container_config_path}.metadata"
  special_args = {
    hostname = var.hostname
  }
}

# nix build vm metadata
module "nix_build_vm_metadata" {
  source    = "github.com/nix-community/nixos-anywhere//terraform/nix-build"
  attribute = "${local.nixos_vm_config_path}.metadata"
  special_args = {
    hostname = var.hostname
  }
}

# push container image to incus
resource "incus_image" "incus_container_image" {
  aliases = ["nixos/custom/container"]
  source_file = {
    data_path     = "${module.nix_build_container_image.result.out}/nixos-lxc-image-x86_64-linux.squashfs"
    metadata_path = format("/%s", tolist(fileset("/", format("%s/tarball/*", module.nix_build_container_metadata.result.out)))[0])
  }
}
# push vm image to incus
resource "incus_image" "incus_vm_image" {
  aliases = ["nixos/custom/virtual-machine"]
  source_file = {
    data_path     = "${module.nix_build_vm_image.result.out}/nixos.qcow2"
    metadata_path = format("/%s", tolist(fileset("/", format("%s/tarball/*", module.nix_build_vm_metadata.result.out)))[0])
  }
}

output "container" {
  value = one(incus_image.incus_container_image.aliases)
}

output "virtual-machine" {
  value = one(incus_image.incus_vm_image.aliases)
}
