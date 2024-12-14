return {
	"2kabhishek/nerdy.nvim",
	dependencies = {
		"stevearc/dressing.nvim",
		"nvim-telescope/telescope.nvim",
	},
	cmd = "Nerdy",
	vim.keymap.set("n", "<leader>nf", "<cmd>Nerdy<CR>", { desc = "Fuzzy find Nerd Fonts" }),
}
