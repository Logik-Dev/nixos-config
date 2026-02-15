{ inputs, ... }:
let
  inherit (inputs.self.lib.mk-os) linux darwin;

  flake.nixosConfigurations.sonicmaster = linux "sonicmaster";

  flake.nixosConfigurations.hyper = linux "hyper";

  flake.darwinConfigurations.m4 = darwin "m4";

in
{
  inherit flake;
}
