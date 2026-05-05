{ ... }:
{
  flake.modules.darwin.common =
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
        taps = [
          "anomalyco/homebrew-tap"
        ];
        brews = [ "opencode" ];
        casks = [
          "audacity"
          "discord"
          "gitify"
          "lm-studio"
          "secretive"
          "slack"
          "sonos"
          "spotify"
          "steam"
          "syncthing"
          "utm"
          "visual-studio-code"
        ];
      };
    };
}
