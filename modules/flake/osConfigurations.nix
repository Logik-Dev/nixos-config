{ inputs, ... }:
let
  inherit (inputs.self.lib.mk-os) linux;

  flake.nixosConfigurations.sonicmaster = linux "sonicmaster";

  flake.nixosConfigurations.hyper = linux "hyper";

in
{
  inherit flake;
}
