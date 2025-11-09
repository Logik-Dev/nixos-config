{ ... }:
let

  flake.modules.homeManager.nixvim.imports = [ conform ];

  flake.modules.homeManager.common =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.prettier ];
    };

  conform =
    { lib, pkgs, ... }:
    {
      programs.nixvim.plugins.conform-nvim = {
        enable = true;
        settings = {
          formatters_by_ft.nix = [ "nixfmt" ];
          formatters_by_ft.javascript = [ "prettier" ];
          formatters_by_ft.typescript = [ "prettier" ];
          formatters.nixfmt.command = lib.getExe pkgs.nixfmt-rfc-style;
          format_on_save = {
            lsp_format = "fallback";
            timeout_ms = 500;
          };
        };
      };
    };
in
{
  inherit flake;
}
