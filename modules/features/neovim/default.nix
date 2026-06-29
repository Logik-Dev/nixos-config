{ inputs, ... }:
let

  flake.modules.nixos.neovim.imports = [ linux ];

  flake.modules.darwin.neovim.imports = [ darwin ];

  darwin =
    { ... }:
    {
      imports = [ inputs.nixvim.nixDarwinModules.nixvim ];
    };

  linux =
    { ... }:
    {
      imports = [ inputs.nixvim.nixosModules.nixvim ];
    };

in
{
  inherit flake;
}
