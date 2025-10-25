{ inputs, ... }:
let
  flake.modules.nixos.common.imports = [ inputs.nur.modules.nixos.default ];
  flake.modules.homeManager.common.imports = [ inputs.nur.modules.homeManager.default ];
in
{
  inherit flake;
}
