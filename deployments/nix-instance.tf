# global var to pass as special_args
data "sops_file" "nix_globals" {
  source_file = "./secrets.yaml"
}


module "nix-build-instance" {
  for_each  = incus_instance.instance
  source    = "github.com/nix-community/nixos-anywhere//terraform/nix-build"
  attribute = ".#nixosConfigurations.${each.value.name}.config.system.build.toplevel"
  special_args = {
    hostname = each.value.name
    username = data.sops_file.nix_globals.data["username"]
    email    = data.sops_file.nix_globals.data["email"]
    domain   = data.sops_file.nix_globals.data["domain"]
  }
}

module "nix-deploy-instance" {
  for_each     = incus_instance.instance
  source       = "github.com/nix-community/nixos-anywhere//terraform/nixos-rebuild"
  nixos_system = module.nix-build-instance[each.key].result.out
  target_host  = local.machines[each.key].ipv4
  target_user  = data.sops_file.nix_globals.data["username"]
}
