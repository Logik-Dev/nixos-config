{ inputs, ... }:
{

  flake.modules.homeManager.dev.imports = with inputs.self.modules.homeManager; [
    dev-direnv
    git
    jj
  ];
}
