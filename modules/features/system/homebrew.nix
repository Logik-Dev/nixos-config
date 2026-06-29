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
          #cleanup = "uninstall";
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
          "syncthing-app"
          "utm"
          "visual-studio-code"
        ];
      };
    };
}
