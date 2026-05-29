{ inputs, ... }:
let

  flake.modules.nixos.common.imports = [ linux ];

  flake.modules.darwin.common.imports = [ darwin ];

  darwin =
    { ... }:
    {
      imports = [ inputs.nixvim.nixDarwinModules.nixvim ];
    };

  linux =
    { ... }:
    {
      imports = [ inputs.nixvim.nixDarwinModules.nixvim ];
    };

in
{
  inherit flake;
}
