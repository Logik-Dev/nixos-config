
# Build nixos container base image with nix build 
module "container-image-build" {
  source    = "github.com/nix-community/nixos-anywhere//terraform/nix-build"
  attribute = "../.#nixosConfigurations.container.config.system.build.squashfs"
  special_args = {
    hostname = "nixos"
    username = nonsensitive(data.sops_file.nix_globals.data["username"])
    email    = nonsensitive(data.sops_file.nix_globals.data["email"])
    domain   = nonsensitive(data.sops_file.nix_globals.data["domain"])

  }
}

# Build nixos container base image metadata with nix build
module "container-metadata-build" {
  source    = "github.com/nix-community/nixos-anywhere//terraform/nix-build"
  attribute = "../.#nixosConfigurations.container.config.system.build.metadata"
  special_args = {
    hostname = "nixos"
  }
}

# Import image to incus remote
resource "incus_image" "container-image" {
  aliases = ["nixos/custom/container"]
  source_file = {
    data_path     = format("%s/nixos-lxc-image-x86_64-linux.squashfs", module.container-image-build.result.out)
    metadata_path = format("/%s", tolist(fileset("/", format("%s/tarball/*", module.container-metadata-build.result.out)))[0])
  }
}

