{ inputs, ... }:
let

  flake.modules.nixos.neovim.imports = [ linux ];

  linux =
    { ... }:
    {
      imports = [ inputs.nixvim.nixosModules.nixvim ];
    };

in
{
  inherit flake;
}
