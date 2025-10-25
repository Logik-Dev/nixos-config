let

  map = action: desc: {
    inherit action;
    options.desc = "Telescope: ${desc}";
  };

  flake.modules.homeManager.nixvim = {
    programs.nixvim.plugins.telescope = {
      enable = true;
      extensions.ui-select = {
        enable = true;
      };
      settings.defaults.wrap_results = true;
      keymaps = {
        "<leader>sf" = map "find_files" "Search for files";
        "<leader>so" = map "oldfiles" "Recent files";
        "<leader>ss" = map "live_grep" "Search for string";
        "<leader>sb" = map "buffers" "Buffers";
        "<leader>sk" = map "keymaps" "Keymaps";
        "<leader>sr" = map "lsp_references" "LSP references";
        "<leader>d" = map "diagnostics" "Diagnostics";
        "<leader>sd" = map "lsp_definitions" "LSP definitions";
        "<leader>sa" = map "lsp_code_actions" "LSP code actions";
        "<leader>sD" = map "lsp_type_definitions" "LSP type definitions";
        "<leader>rl" = map "reloader" "List lua modules and reload on <CR>";
        "<leader>sm" = map "man_pages" "Search manpages";
      };
    };

  };
in
{
  inherit flake;
}
