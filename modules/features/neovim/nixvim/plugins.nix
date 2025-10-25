{
  flake.modules.homeManager.nixvim = {
    programs.nixvim.plugins = {
      tiny-inline-diagnostic.enable = true;
      trouble.enable = true;
      nui.enable = true;
      web-devicons.enable = true;
      neo-tree.enable = true;
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
}
