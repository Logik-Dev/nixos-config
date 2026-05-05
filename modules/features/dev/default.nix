{ inputs, ... }:
{

  flake.modules.homeManager.dev.imports = with inputs.self.modules.homeManager; [
    git
    jj
    #ollama
  ];
}
