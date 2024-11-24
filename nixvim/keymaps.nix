{ lib, helpers, ... }:
{
  keymaps =
    let
      nmap =
        kms:
        lib.attrsets.mapAttrsToList (key: action: {
          inherit key action;
          mode = "n";
        }) kms;
    in
    helpers.keymaps.mkKeymaps { options.silent = true; } (nmap {
      "tr" = "<cmd>Neotree<CR>";
      "<leader>tt" = "<cmd>Neotree toggle<CR>";

      "<leader>ff" = "<cmd>Telescope find_files<CR>";
      "<leader>fg" = "<cmd>Telescope live_grep<CR>";
      "<leader>fk" = "<cmd>Telescope keymaps<CR>";
      "<leader>fb" = "<cmd>Telescope buffers<CR>";
      "<leader>fo" = "<cmd>Telescope oldfiles<CR>";
    });
}
