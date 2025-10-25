{ inputs, ... }:
{
  flake.modules.homeManager.desktop.imports = with inputs.self.modules.homeManager; [
    browsers
  ];
}
