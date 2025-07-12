return {
  "neovim/nvim-lspconfig",
  event = { "BufReadPre", "BufNewFile" },
  dependencies = { 'saghen/blink.cmp' },

  config = function()
    -- diagnostics virtual lines
    vim.diagnostic.config({ virtual_lines = { current_line = true } })

    -- disable auto select completion
    vim.cmd("set completeopt+=fuzzy")

    -- enable rounded border on floating window
    vim.o.winborder = 'rounded'
  end
}
