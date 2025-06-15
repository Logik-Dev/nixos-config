terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "0.3.1"
    }
  }
}


# push container image to incus
resource "incus_image" "incus_container_image" {
  aliases = ["nixos/custom/container"]
  source_file = {
    data_path     = "./generated/container-image.squashfs"
    metadata_path = "./generated/container-metadata.tar.xz"
  }
}
# push vm image to incus
resource "incus_image" "incus_vm_image" {
  aliases = ["nixos/custom/virtual-machine"]
  source_file = {
    data_path     = "./generated/vm.qcow2"
    metadata_path = "./generated/vm-metadata.tar.xz"
  }
}

output "container" {
  value = one(incus_image.incus_container_image.aliases)
}

output "virtual-machine" {
  value = one(incus_image.incus_vm_image.aliases)
}
