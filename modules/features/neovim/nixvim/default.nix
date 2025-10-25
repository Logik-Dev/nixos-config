{ inputs, ... }:
{

  flake.modules.homeManager.nixvim = {
    imports = [ inputs.nixvim.homeModules.nixvim ];

    programs.nixvim = {
      enable = true;
      defaultEditor = true;
      nixpkgs.useGlobalPackages = true;
      viAlias = true;
      vimAlias = true;
      plugins.actions-preview.enable = true;
      colorschemes.tokyonight.enable = true;
      colorschemes.tokyonight.settings.light_style = "night";
      autoCmd = [
        {
          event = [ "TextYankPost" ];
          callback = {
            __raw = "function() vim.highlight.on_yank() end";
          };
        }
      ];
    };
  };
}
