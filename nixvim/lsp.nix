{
  lib,
  pkgs,
  helpers,
  flake,
  ...
}:

{
  plugins.web-devicons = {
    enable = true;
  };
  plugins.luasnip = {
    enable = true;
  };

  plugins.lspkind = {
    enable = true;
    cmp = {
      enable = true;
      menu = {
        nvim_lsp = "[LSP]";
        nvim_lua = "[api]";
        path = "[path]";
        luasnip = "[snip]";
        buffer = "[buffer]";
        neorg = "[neorg]";
        nixpkgs_maintainers = "[nixpkgs]";

      };

    };
  };

  plugins.nvim-lightbulb = {
    enable = true;
    settings.autocmd.enabled = true;
  };
  plugins.lsp = {
    enable = true;

    keymaps = {
      silent = true;

      lspBuf = {
        "gd" = "definition";
        "gD" = "declaration";
        "ca" = "code_action";
        "ff" = "format";
        "K" = "hover";
      };
    };

    servers = {
      nixd = {
        enable = true;
        package = null;
        settings = {
          nixpkgs.expr = "import (builtins.getFlake \"/home/logikdev/Parts\").inputs.nixpkgs { }";
          formatting.command = [ (lib.getExe pkgs.nixfmt-rfc-style) ];
          extraOptions = {
            offset_encoding = "utf-8";
          };
          options =
            let
              #getFlake = ''(builtins.getFlake "${flake}")'';
              getFlake = ''(builtins.getFlake "/home/logikdev/Parts")'';
            in
            {
              nixos.expr = "${getFlake}.nixosConfigurations.sonicmaster.options";
              nixvim.expr = "${getFlake}.packages.${pkgs.system}.nixvimPkg.options";
              home-manager.expr = ''${getFlake}.homeConfigurations."logikdev@sonicmaster".options'';
            };
        };
      };
      bashls.enable = true;
      ts_ls.enable = true;
      basedpyright.enable = true;
      yamlls.enable = true;
    };
  };

  plugins.rustaceanvim = {
    enable = true;

    settings.server = {
      default_settings.rust-analyzer = {
        cargo.features = "all";
        checkOnSave = true;
        check.command = "clippy";
        rustc.source = "discover";
      };
    };
  };

}
