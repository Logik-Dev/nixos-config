{
  flake.modules.homeManager.nixvim = {
    programs.nixvim.plugins = {

      treesitter = {
        enable = true;
        nixvimInjections = true;
        settings.highlight.enable = true;
      };

      treesitter-refactor = {
        enable = false;
        settings = {
          highlight_definitions = {
            enable = true;
            # Set to false if you have an `updatetime` of ~100.
            clear_on_cursor_move = false;
          };
        };
      };

      hmts.enable = true;
    };
  };
}
