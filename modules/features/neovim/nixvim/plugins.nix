_:
let

  flake.modules.nixos.neovim.imports = [ plugins ];

  plugins = _: {
    programs.nixvim.plugins = {
      emmet.enable = true;
      tiny-inline-diagnostic.enable = true;
      trouble.enable = true;
      nui.enable = true;
      web-devicons.enable = true;
      web-devicons.autoLoad = true;
      neo-tree.enable = true;
      otter.enable = true;
      comment.enable = true;
      nvim-autopairs.enable = true;
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
