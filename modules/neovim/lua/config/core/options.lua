-- Globals
vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.g.have_nerd_font = true

-- Options
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.autoindent = true

vim.opt.number = true
vim.opt.relativenumber = true

vim.opt.mouse = "a"

vim.opt.showmode = false

vim.opt.clipboard = "unnamedplus"

-- Undo history
vim.opt.undofile = true

-- Search settings
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- Signcolumn always on
vim.opt.signcolumn = "yes"

-- Performance tweaks
vim.opt.updatetime = 250
vim.opt.timeoutlen = 300

-- Split window behavior
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Live substitution preview
vim.opt.inccommand = "split"

-- Cursor settings
vim.opt.cursorline = true
vim.opt.scrolloff = 10

-- Highlight search results
vim.opt.hlsearch = true
