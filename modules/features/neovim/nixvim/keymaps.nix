{ ... }:
let

  keymap = mode: desc: key: action: {
    inherit action key mode;
    options = {
      inherit desc;
      silent = false;
    };
  };

  normal =
    desc: key: action:
    keymap [ "n" ] desc key action;

  insert =
    desc: key: action:
    keymap [ "i" ] desc key action;

  rebuild = ''
    <Cmd>lua
    function rebuild()
      vim.cmd("terminal nh os switch")
      vim.cmd("source ~/.config/nvim/init.lua")
    end
    rebuild()
  '';

  flake.modules.homeManager.nixvim = {
    programs.nixvim.keymaps = [
      (normal "Toggle Neotree" "<leader>e" "<Cmd>Neotree toggle<CR>")
      (normal "Nixos rebuild and reload nvim" "<leader>nrs" rebuild)
      (normal "Save" "<leader>w" "<Cmd>w<CR>")
      (normal "Quit" "<leader>q" "<Cmd>q<CR>")
      (normal "Page down" "<leader><leader>d" "<C-d>zz")
      (normal "Page up" "<leader><leader>u" "<C-u>zz")
      (normal "Save and Quit" "<leader>wq" "<Cmd>wq<CR>")
      (normal "Code action preview" "<leader>ca" ":lua require('actions-preview').code_actions()<CR>")
      (insert "Escape" "jk" "<Esc>")
      (insert "Escape" "kj" "<Esc>")
    ];
  };
in
{
  inherit flake;
}
