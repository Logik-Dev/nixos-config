{
  pkgs,
  config,
  helpers,
  lib,
  ...
}:
{

  imports = [
    ./completion.nix
    ./keymaps.nix
    ./lsp.nix
    ./options.nix
    ./plugins.nix
  ];

  viAlias = true;
  vimAlias = true;

  colorschemes.tokyonight = {
    settings.style = "night";
    enable = true;
  };

  performance = {
    byteCompileLua = {
      enable = true;
      nvimRuntime = true;
      configs = true;
      plugins = true;
    };

    combinePlugins = {
      enable = true;
      standalonePlugins = [
        "vimplugin-treesitter-grammar-nix"
        "nvim-treesitter"
      ];
    };
  };
}
