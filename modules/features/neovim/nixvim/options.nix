{ ... }:
let

  flake.modules.nixos.common.imports = [ options ];

  flake.modules.darwin.common.imports = [ options ];

  options =
    { pkgs, lib, ... }:
    {
      programs.nixvim = {
        clipboard = {
          register = "unnamedplus";
          providers = lib.mkIf pkgs.stdenv.isLinux {
            wl-copy.enable = true;
          };
        };

        globals = {
          mapleader = " ";
          maplocalleader = " ";
        };

        opts = {
          updatetime = 100;
          hidden = true;
          swapfile = false;
          undofile = true;
          number = true;
          relativenumber = true;
          mouse = "a";
          shiftwidth = 4;
          tabstop = 4;
          expandtab = true;
          autoindent = true;
          incsearch = true;
          ignorecase = true;
          smartcase = true;
          scrolloff = 8;
          cursorline = false;
          cursorcolumn = false;
          signcolumn = "yes";
          fileencoding = "utf-8";
          termguicolors = true;
          spell = false;
          wrap = false;
        };
      };
    };
in
{
  inherit flake;
}
