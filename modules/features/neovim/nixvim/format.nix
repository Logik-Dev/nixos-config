{ ... }:
let

  flake.modules.homeManager.nixvim.imports = [ conform ];

  conform =
    { lib, pkgs, ... }:
    {
      programs.nixvim.plugins.conform-nvim = {
        enable = true;
        settings = {
          formatters_by_ft.nix = [ "nixfmt" ];

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
