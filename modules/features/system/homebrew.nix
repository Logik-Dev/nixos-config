_: {
  flake.modules.darwin.common = _: {

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
      brews = [
        "glow"
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
