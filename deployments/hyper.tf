locals {
  hyper-ipv4 = "192.168.10.100"
}

# DO NOT REMOVE this resource 
# It handles install one time and rebuild when needed (2 resources created)
module "deploy-hyper" {
  source                 = "github.com/nix-community/nixos-anywhere//terraform/all-in-one"
  nixos_system_attr      = ".#nixosConfigurations.hyper.config.system.build.toplevel"
  nixos_partitioner_attr = ".#nixosConfigurations.hyper.config.system.build.diskoScript"
  nixos_facter_path      = "../machines/hyper/facter.json"
  install_user           = nonsensitive(data.sops_file.globals.data["username"])
  target_user            = nonsensitive(data.sops_file.globals.data["username"])
  target_host            = local.hyper-ipv4
  instance_id            = local.hyper-ipv4
  extra_files_script     = "${path.module}/scripts/decrypt-ssh-secrets.sh"
  special_args = {
    hostname = "hyper"
    username = nonsensitive(data.sops_file.globals.data["username"])
    email    = nonsensitive(data.sops_file.globals.data["email"])
    domain   = nonsensitive(data.sops_file.globals.data["domain"])

  }

}

