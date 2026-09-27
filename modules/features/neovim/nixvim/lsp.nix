_:
let
  flake.modules.nixos.neovim.imports = lsp;

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
  nix =
    { config, ... }:
    let
      hostName = config.networking.hostName;
      flakePath = config.constants.users.logikdev.flakeDir;
      withHost = opts: ''(builtins.getFlake "${flakePath}").${opts}'';
      osConfig = "nixosConfigurations.${hostName}.options";
      homeManagerConfig = ''homeConfigurations."logikdev@${hostName}".options'';
    in
    {
      programs.nixvim.plugins.lspconfig.enable = true;
      programs.nixvim.lsp.servers = {
        nil_ls.enable = true;
        nixd = {
          enable = true;

          config.settings.nixd = {
            nixpkgs.expr = "import <nixpkgs> {}";
            options = {
              nixos.expr = withHost osConfig;
              homeManager.expr = withHost homeManagerConfig;
              nixvim.expr = withHost ''homeConfigurations."logikdev@${hostName}".options.programs.nixvim.type.getSubOptions []'';
              flakeParts.expr = withHost "debug.options";
            };
          };
        };
      };
    };

in
{
  inherit flake;
}
