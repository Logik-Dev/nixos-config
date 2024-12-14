return {
	"catppuccin/nvim",
	name = "catppuccin",
	config = function()
		require("catppuccin").setup({
			flavour = "mocha", -- latte, frappe, macchiato, mocha
			background = { dark = "mocha", light = "latte" }, -- darker, cooler, lighter, warmer, macchiato, frappe
			transparent_background = true,
			integrations = {
				treesitter = true, -- Integrate with Treesitter
				lsp_trouble = true, -- Integrate with LSP trouble
				gitsigns = true, -- Git integration
				telescope = true, -- Telescope integration
				neotree = true, -- Neo-tree integration
				cmp = true, -- nvim-cmp integration
				mason = true,
				which_key = true,
			},
		})

		-- Set the colorscheme
		vim.cmd.colorscheme("catppuccin")
	end,
}
