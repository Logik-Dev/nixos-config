{
  flake.modules.homeManager.desktop = {
    programs.wezterm = {
      enable = true;
      extraConfig = ''
        return {
              font = wezterm.font "FiraCode Nerd Font",
              hide_tab_bar_if_only_one_tab = true,
              window_decorations = "RESIZE",
              window_padding = {
                bottom = 20
              },
        }
      '';
    };
  };
}
