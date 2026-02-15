{ ... }:
let

  flake.modules.nixos.common.imports = [ plugins ];

  flake.modules.darwin.common.imports = [ plugins ];

  plugins =
    { ... }:
    {
      programs.nixvim.plugins = {
        tiny-inline-diagnostic.enable = true;
        trouble.enable = true;
        nui.enable = true;
        web-devicons.enable = true;
        web-devicons.autoload = true;
        neo-tree.enable = true;
        otter.enable = true;
        comment.enable = true;
        neo-tree.settings = {
          window.mappings = {
            l = "open";
            h = "close_node";
            "<space>" = "none";

          };
        };

      };
    };
in
{

  inherit flake;
}
