{ ... }:
let

  flake.modules.homeManager.nixvim.imports = [ blink ];
  blink = {
    programs.nixvim.plugins.blink-cmp = {
      enable = true;
      settings = {
        completion.documentation.auto_show = true;
        keymap = {
          preset = "enter";
          "<Down>" = [
            "snippet_forward"
            "fallback"
          ];
          "<Up>" = [
            "snippet_backward"
            "fallback"
          ];
          "<Tab>" = [
            "select_next"
            "fallback"
          ];
          "<S-Tab>" = [
            "select_prev"
            "fallback"
          ];
        };
      };
    };
  };

in
{
  inherit flake;
}
