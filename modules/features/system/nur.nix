{ inputs, ... }:
let
  flake.modules.nixos.common.imports = [ inputs.nur.modules.nixos.default ];
in
{
  inherit flake;
}
