require("config.core.options")
require("config.core.keymaps")
require("config.lazy")

-- lsp
local capabilities = require('blink.cmp').get_lsp_capabilities()
vim.lsp.config('*', { capabilities = capabilities })
vim.lsp.enable('nixd')
vim.lsp.enable('lua_ls')
