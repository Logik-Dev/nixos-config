# NixOS Image Generation and Import

# Generate NixOS base image
resource "null_resource" "generate_nixos_vm_image" {
  provisioner "local-exec" {
    command     = "nix run .#image-builder"
    working_dir = ".."
  }
}

# Import generated image into Incus
resource "incus_image" "nixos_vm" {
  depends_on = [null_resource.generate_nixos_vm_image]

  source_file = {
    metadata_path = "./generated/vm-metadata.tar.xz"
    data_path = "./generated/vm.qcow2"
  }
  
  aliases = ["nixos-vm"]
}
