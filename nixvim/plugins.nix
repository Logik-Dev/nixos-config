{ pkgs, config, ... }:
{

  plugins = {
    # lualine
    lualine.enable = true;

    # conform
    conform-nvim = {
      enable = true;
      #settings = {
      #  default_format_opts = {
      #lsp_format = "fallback";
      #};
      #format_on_save.lsp_format = "fallback";
      #};
    };
    gitsigns.enable = true;

    gitmessenger.enable = true;

    telescope = {
      enable = true;
      extensions = {
        ui-select.enable = true;
      };
      settings = {
        defaults.layout_strategy = "vertical";
      };
    };

    treesitter = {
      enable = true;

      settings = {
        indent.enable = true;
        highlight.enable = true;
      };

      nixvimInjections = true;

      grammarPackages = with config.plugins.treesitter.package.passthru.builtGrammars; [
        bash
        diff
        dockerfile
        gitattributes
        gitcommit
        gitignore
        git_rebase
        html
        ini
        json
        lua
        make
        markdown
        markdown_inline
        nix
        python
        rust
        toml
        vim
        vimdoc
        yaml
        mermaid
      ];
    };

    treesitter-refactor = {
      enable = true;
      highlightDefinitions = {
        enable = true;
        clearOnCursorMove = true;
      };
      smartRename = {
        enable = true;
      };
      navigation = {
        enable = true;
      };
    };

    treesitter-context = {
      enable = true;
    };

    comment = {
      enable = true;
    };

    neo-tree = {
      enable = true;
    };

    which-key.enable = true;
  };
  extraPlugins = with pkgs.vimPlugins; [
    telescope-ui-select-nvim
    vim-snippets
  ];
}
