{ inputs, ... }:
{

  flake.modules.homeManager.common.imports = with inputs.self.modules.homeManager; [ nixvim ];
}
