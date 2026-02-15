{ ... }:
{
  flake.modules.darwin.homebrew =
    { ... }:
    {

      system.primaryUser = "logikdev";
      homebrew = {
        enable = true;
        enableFishIntegration = true;
        enableZshIntegration = true;
        global.autoUpdate = true;
        onActivation = {
          autoUpdate = true;
          cleanup = "zap";
          upgrade = true;
        };
        casks = [
          "alacritty"
          "audacity"
          "discord"
          "secretive"
          "slack"
          "sonos"
          "spotify"
          "steam"
          "utm"
          "visual-studio-code"
        ];
      };
    };
}
