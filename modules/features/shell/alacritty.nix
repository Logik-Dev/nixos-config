{ ... }:
{
  flake.modules.homeManager.desktop =
    {
      pkgs,
      lib,
      ...
    }:
    {
      programs.alacritty = {
        enable = true;
        theme = "tokyo_night";
        settings = {
          font.normal.family = "FiraCode Nerd Font";
          terminal.shell = "${pkgs.fish}/bin/fish";
          window = {
            padding.x = 5;
            padding.y = 5;
            startup_mode = "Maximized";
            opacity = 0.7;
            blur = true;
            decorations = "Buttonless";
          }
          // lib.optionalAttrs pkgs.stdenv.isDarwin { option_as_alt = "OnlyLeft"; };
        };
      };
    };
}
