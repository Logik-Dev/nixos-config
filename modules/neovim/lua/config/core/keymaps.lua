-- Keymap helper function
local function map(mode, key, action, opts)
	local options = { noremap = true, silent = true, desc = opts.desc or "" }
	vim.api.nvim_set_keymap(mode, key, action, options)
end

-- Exit insert mode with 'jk'
map("i", "jk", "<ESC>", { desc = "Exit insert mode" })

-- Clear search highlighting
map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlighting" })

-- Save
map("n", "<leader>w", "<cmd>:w<CR>", { desc = "Save file" })
