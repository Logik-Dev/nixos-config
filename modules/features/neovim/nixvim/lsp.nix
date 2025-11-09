{ ... }:
let
  flake.modules.homeManager.nixvim.imports = [
    bash
    common
    nix
    rust
    ts
    yaml
  ];

  common = {
    programs.nixvim.lsp.inlayHints.enable = true;
  };

  bash = {
    programs.nixvim.lsp.servers.bashls.enable = true;
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
              flakeOptions = opts: ''(builtins.getFlake "/home/logikdev/Homelab/Nixos").${opts}'';
            in
            {
              nixos.expr = flakeOptions "nixosConfigurations.sonicmaster.options";
              homeManager.expr = flakeOptions ''homeConfigurations."logikdev@sonicmaster".options'';
              nixvim.expr = flakeOptions ''homeConfigurations."logikdev@sonicmaster".options.programs.nixvim.type.getSubOptions []'';
              flakeParts.expr = flakeOptions "debug.options";
            };
        };
      };
    };
  };

in
{
  inherit flake;
}
