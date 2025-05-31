terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "0.3.1"
    }
  }
}

locals {
  nixos_config_path = "../.#nixosConfigurations.${var.type}.config.system.build"
  image_attribute   = var.type == "container" ? "squashfs" : "qemuImage"
  image_aliases     = ["nixos/custom/${var.type}"]
  image_artifact    = var.type == "container" ? "nixos-lxc-image-x86_64-linux.squashfs" : "nixos.qcow2"
}

# nix build image
module "nix_build_image" {
  source    = "github.com/nix-community/nixos-anywhere//terraform/nix-build"
  attribute = "${local.nixos_config_path}.${local.image_attribute}"
  special_args = {
    hostname = var.hostname
    username = var.username
  }
}

# nix build metadata
module "nix_build_metadata" {
  source    = "github.com/nix-community/nixos-anywhere//terraform/nix-build"
  attribute = "${local.nixos_config_path}.metadata"
  special_args = {
    hostname = var.hostname
  }
}

# push image to incus
resource "incus_image" "image" {
  aliases = local.image_aliases
  source_file = {
    data_path     = "${module.nix_build_image.result.out}/${local.image_artifact}"
    metadata_path = format("/%s", tolist(fileset("/", format("%s/tarball/*", module.nix_build_metadata.result.out)))[0])
  }
}

output "aliases" {
  value = incus_image.image.aliases
}
