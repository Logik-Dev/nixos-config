{
  flake.modules.homeManager.common =
    { pkgs, ... }:
    {
      programs.zellij = {
        enable = true;
        enableFishIntegration = !pkgs.stdenv.isDarwin;
        settings = {
          default_shell = "fish";
          theme = "cyber-dark";
          mouse_mode = false;
          attachExistingSession = true;
        };
      };
    };
}
