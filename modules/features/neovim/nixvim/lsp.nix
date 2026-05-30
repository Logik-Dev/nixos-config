{ ... }:
let
  flake.modules.nixos.neovim.imports = lsp;

  flake.modules.darwin.neovim.imports = lsp;

  lsp = [
    #asm
    angular
    bash
    common
    emmet
    nix
    organizeImports
    rust
    ts
    tailwind
    yaml
  ];

  angular = {
    programs.nixvim.lsp.servers.angularls.enable = true;

  };

  common = {
    programs.nixvim.lsp.inlayHints.enable = true;
  };

  bash = {
    programs.nixvim.lsp.servers.bashls.enable = true;
  };

  emmet = {
    programs.nixvim.lsp.servers.emmet_ls.enable = true;
  };

  yaml = {
    programs.nixvim.lsp.servers.yamlls.enable = true;
  };

  ts = {
    programs.nixvim.lsp.servers.ts_ls.enable = true;
  };

  rust = {
    programs.nixvim.lsp.servers.rust_analyzer.enable = true;
  };

  tailwind = {
    programs.nixvim.lsp.servers.tailwindcss.enable = true;

  };
  organizeImports = {
    programs.nixvim.autoCmd = [
      {
        event = [ "BufWritePre" ];
        pattern = [
          "*.ts"
          "*.rs"
        ];
        callback = {
          __raw = ''
            function()
              local params = {
                command = "_typescript.organizeImports",
                arguments = {vim.api.nvim_buf_get_name(0)},
                title = ""
              }
              vim.lsp.buf.execute_command(params)
            end
          '';
        };
      }
    ];

  };
  nix = {
    programs.nixvim.plugins.lspconfig.enable = true;
    programs.nixvim.lsp.servers = {
      nil_ls.enable = true;
      nixd = {
        enable = true;

        config.settings.nixd = {
          nixpkgs.expr = "import <nixpkgs> {}";
          options =
            let
              withSonicmaster = opts: ''(builtins.getFlake "/home/logikdev/Homelab/Nixos").${opts}'';
              withM4 = opts: ''(builtins.getFlake "/Users/logikdev/Homelab/Nixos").${opts}'';
            in
            {
              #nixos.expr = withSonicmaster "nixosConfigurations.sonicmaster.options";
              nixos.expr = withM4 "darwinConfigurations.m4.options";
              homeManagerSonimaster.expr = withSonicmaster ''homeConfigurations."logikdev@sonicmaster".options'';
              homeManagerM4.expr = withM4 ''homeConfigurations."logikdev@m4".options'';
              nixvim.expr = withSonicmaster ''homeConfigurations."logikdev@sonicmaster".options.programs.nixvim.type.getSubOptions []'';
              flakeParts.expr = withSonicmaster "debug.options";
            };
        };
      };
    };
  };

in
{
  inherit flake;
}
