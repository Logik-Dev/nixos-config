{ ... }:
let
  flake.modules.nixos.common.imports = lsp;

  flake.modules.darwin.common.imports = lsp;

  lsp = [
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
