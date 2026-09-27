_:
let

  flake.modules.nixos.neovim.imports = [ treesitter ];

  treesitter = _: {
    programs.nixvim.plugins = {

      treesitter = {
        enable = true;
        nixvimInjections = true;
        settings.highlight.enable = true;
        settings.indent.enable = true;
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

in
{
  inherit flake;
}
