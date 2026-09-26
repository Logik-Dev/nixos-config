{
  flake.modules.homeManager.common =
    { pkgs, ... }:
    {
      programs.zellij = {
        enable = true;
        enableFishIntegration = !pkgs.stdenv.isDarwin;
        attachExistingSession = true;
        settings = {
          default_shell = "fish";
          theme = "cyber-noir";
          mouse_mode = false;
        };
      };
    };
}
