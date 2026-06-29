let

  flake.modules.nixos.neovim.imports = [ default ];

  flake.modules.darwin.neovim.imports = [ default ];

  default =
    { ... }:
    {
      programs.nixvim = {
        enable = true;
        nixpkgs.useGlobalPackages = true;
        viAlias = true;
        vimAlias = true;
        plugins.actions-preview.enable = true;

        # tokyonight
        colorschemes.tokyonight.enable = false;
        colorschemes.tokyonight.settings.light_style = "night";

        # catppuccin
        colorschemes.catppuccin.enable = false;
        colorschemes.catppuccin.settings.flavour = "mocha";

        # vscode
        colorschemes.vscode.enable = true;

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
in
{
  inherit flake;
}
