{
  flake.modules.homeManager.dev =
    { pkgs, ... }:
    {
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };

      home.packages = [ pkgs.devenv ];

      programs.fish.shellInitLast = "devenv hook fish | source";
    };
}
