{
  flake.modules.homeManager.desktop =
    { pkgs, ... }:
    {
      programs.zellij = {
        enable = true;
        enableFishIntegration = true;
        #attachExistingSession = true;
        exitShellOnExit = true;
        settings = {
          default_shell = "fish";
          theme = "cyber-dark";
          #mouse_mode = false;
          copy_command = if pkgs.stdenv.isLinux then "wl-copy" else "pbcopy";
        };
      };
    };
}
