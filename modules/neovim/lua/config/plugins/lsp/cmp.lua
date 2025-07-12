return {
	"hrsh7th/nvim-cmp",
	event = "InsertEnter",
	dependencies = {
		"hrsh7th/cmp-nvim-lsp", -- LSP source for nvim-cmp
		"hrsh7th/cmp-buffer", -- Buffer completions
		"hrsh7th/cmp-path", -- Path completions
		"hrsh7th/cmp-cmdline", -- Command-line completions
		"onsails/lspkind-nvim", -- Icons for nvim-cmp
		"L3MON4D3/LuaSnip", -- Snippet engine
		"saadparwaiz1/cmp_luasnip", -- Snippet completions
		"rafamadriz/friendly-snippets", -- useful snippets
	},
	config = function()
		-- Import the required plugins
		local cmp = require("cmp")
		local luasnip = require("luasnip")
		local lspkind = require("lspkind")

		-- loads vscode style snippets from installed plugins (e.g. friendly-snippets)
		require("luasnip.loaders.from_vscode").lazy_load()

		-- Setup nvim-cmp
		cmp.setup({
			completion = {
				completeopt = "menu,menuone,preview,noselect",
			},
			snippet = {
				expand = function(args)
					luasnip.lsp_expand(args.body) -- For LuaSnip users
				end,
			},
			mapping = cmp.mapping.preset.insert({
				["<S-Tab>"] = cmp.mapping.select_prev_item(), -- Navigate to the previous item
				["<Tab>"] = cmp.mapping.select_next_item(), -- Navigate to the next item
				["<C-b>"] = cmp.mapping.scroll_docs(-4), -- Scroll documentation up
				["<C-f>"] = cmp.mapping.scroll_docs(4), -- Scroll documentation down
				["<C-Space>"] = cmp.mapping.complete(), -- Trigger completion
				["<C-e>"] = cmp.mapping.abort(), -- Abort completion
				["<CR>"] = cmp.mapping.confirm({ select = true }), -- Confirm selection
			}),
			sources = cmp.config.sources({
				{ name = "nvim_lsp" }, -- LSP source
				{ name = "luasnip" }, -- Snippet source
				{ name = "buffer" }, -- Buffer source
				{ name = "path" }, -- Path source
			}),
			formatting = {
				format = lspkind.cmp_format({
					mode = "symbol", -- Show only symbol icons
					maxwidth = 50, -- Max width for completion window
					ellipsis_char = "...", -- Ellipsis for truncated entries
				}),
			},
		})

		-- Setup cmdline completions for `/` and `:` (optional)
		cmp.setup.cmdline("/", {
			mapping = cmp.mapping.preset.cmdline(),
			sources = {
				{ name = "buffer" },
			},
		})

		cmp.setup.cmdline(":", {
			mapping = cmp.mapping.preset.cmdline(),
			sources = cmp.config.sources({
				{ name = "path" },
			}, {
				{ name = "cmdline" },
			}),
		})
	end,
}
