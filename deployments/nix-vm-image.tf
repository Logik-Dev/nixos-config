# Build nixos vm base image
module "vm-image-build" {
  source    = "github.com/nix-community/nixos-anywhere//terraform/nix-build"
  attribute = "../.#nixosConfigurations.vm.config.system.build.qemuImage"
  special_args = {
    hostname = "nixos"
    username = nonsensitive(data.sops_file.nix_globals.data["username"])
    email    = nonsensitive(data.sops_file.nix_globals.data["email"])
    domain   = nonsensitive(data.sops_file.nix_globals.data["domain"])

  }
}

# Build nixos VM base image metadata with nix build
module "vm-metadata-build" {
  source    = "github.com/nix-community/nixos-anywhere//terraform/nix-build"
  attribute = "../.#nixosConfigurations.vm.config.system.build.metadata"
  special_args = {
    hostname = "nixos"
  }
}

# Import image to incus remote
resource "incus_image" "vm-image" {
  aliases = ["nixos/custom/vm"]
  source_file = {
    data_path = format("%s/nixos.qcow2", module.vm-image-build.result.out)
    metadata_path = format("/%s", tolist(fileset("/", format("%s/tarball/*", module.vm-metadata-build.result.out)))[0])
  }
}
