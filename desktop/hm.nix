_: {

  fonts.fontconfig.enable = true;

  programs.firefox.enable = true;

  programs.alacritty = {
    enable = true;
    settings = {
      window = {
        decorations = "None";
        opacity = 0.9;
        startup_mode = "Fullscreen";
      };
      font = {
        normal = {
          family = "FiraCode Nerd Font";
          style = "Regular";
        };
        italic = {
          family = "FiraCode Nerd Font";
          style = "Italic";
        };
        bold = {
          family = "FiraCode Nerd Font";
          style = "Bold";
        };

      };
    };
  };
}
