{
  flake.modules.homeManager.dev =
    { pkgs, ... }:
    {
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };

      home.packages = [ pkgs.devenv ];
    };
}
