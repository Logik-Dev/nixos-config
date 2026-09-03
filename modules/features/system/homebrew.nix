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
        global.autoUpdate = false;
        onActivation = {
          autoUpdate = false;
          #cleanup = "uninstall";
          upgrade = false;
        };
        taps = [
          {
            name = "anomalyco/homebrew-tap";
            trusted = true;
          }
        ];
        brews = [
          "glow"
          "opencode"
        ];
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
          "syncthing-app"
          "utm"
          "visual-studio-code"
        ];
      };
    };
}
