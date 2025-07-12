return {

  "neovim/nvim-lspconfig",
  config = function()
    -- nixd


    vim.keymap.set('n', 'gK', function()
      local new_config = not vim.diagnostic.config().virtual_lines
      vim.diagnostic.config({ virtual_lines = new_config })
    end, { desc = 'Toggle diagnostic virtual_lines' })

    -- Lua
    vim.lsp.enable('lua_ls')
  end
}
