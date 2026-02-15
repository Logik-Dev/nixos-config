{ inputs, ... }:
{
  flake.modules.homeManager.dev.imports = with inputs.self.modules.homeManager; [
    ai-agent
    git
    jj
  ];
}
