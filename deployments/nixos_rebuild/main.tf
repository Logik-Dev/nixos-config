
module "nix_build" {
  source       = "github.com/nix-community/nixos-anywhere//terraform/nix-build"
  attribute    = "../.#nixosConfigurations.${var.special_args.hostname}.config.system.build.toplevel"
  special_args = var.special_args
}

module "nixos_rebuild" {
  source                = "github.com/nix-community/nixos-anywhere//terraform/nixos-rebuild"
  nixos_system          = module.nix_build.result.out
  target_host           = var.ipv4
  target_user           = var.special_args.username
  ignore_systemd_errors = true
}
