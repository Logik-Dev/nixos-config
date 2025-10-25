{
  flake.modules.homeManager.browsers =
    { pkgs, ... }:
    {
      programs.chromium = {
        enable = true;
        package = pkgs.brave;
      };

    };
}
