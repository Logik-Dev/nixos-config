{
  flake.modules.homeManager.desktop = {
    programs.alacritty = {
      enable = true;
      theme = "tokyo_night";
      settings = {
        font.normal.family = "FiraCode Nerd Font";
        window = {
          decorations = "None";
          startup_mode = "Fullscreen";
        };
      };
    };
  };
}
