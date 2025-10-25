{
  flake.modules.homeManager.nixvim = {
    programs.nixvim = {
      clipboard = {
        register = "unnamedplus";
        providers.wl-copy.enable = true;
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

}
