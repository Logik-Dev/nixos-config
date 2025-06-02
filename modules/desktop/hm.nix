{ pkgs, ... }:
{

  gtk.enable = true;

  fonts.fontconfig.enable = true;

  programs.firefox.enable = true;
  programs.brave.enable = true;

  home.packages = with pkgs; [
    halloy
  ];

  programs.zellij = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
  };

  # fix problem with mouse cursor transparency
  home.sessionVariables."XCURSOR_THEME" = "Adwaita";

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
          family = "FiraCodeNerdFont";
          style = "Regular";
        };
        italic = {
          family = "FiraCodeNerdFont";
          style = "Italic";
        };
        bold = {
          family = "FiraCodeNerdFont";
          style = "Bold";
        };

      };
    };
  };
}
