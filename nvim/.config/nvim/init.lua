vim.o.clipboard = "unnamedplus"    -- Use system clipboard
vim.o.expandtab = true             -- Use space instead of tabs
vim.o.hidden = true                -- Allow navigating with unsaved changes
vim.o.mouse = "a"                  -- Enable mouse support
vim.o.shiftwidth = 2               -- Shift by 2 spaces when using << and >>
vim.o.showmode = false             -- Hide the mode indicator
vim.o.softtabstop = 2              -- Move forward 2 spaces with pressing tab
vim.o.tabstop = 2                  -- Set tab to 2 spaces

vim.wo.colorcolumn = "80"          -- Set an 80 width column border
vim.wo.relativenumber = true       -- Show relative line numbers in gutter
vim.wo.signcolumn = "number"       -- Merge sign column and number column

vim.g.mapleader = " "              -- Set space as the leader key

                                   -- Keep selection when indenting
vim.api.nvim_set_keymap('v', '<', '<gv', { noremap = true })
vim.api.nvim_set_keymap('v', '>', '>gv', { noremap = true })

                                   -- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "https://github.com/folke/lazy.nvim.git",
                  "--branch=stable", "--filter=blob:none", lazypath, })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({            -- Specify plugins
  "navarasu/onedark.nvim",
  {"nvim-lualine/lualine.nvim", dependencies={'nvim-tree/nvim-web-devicons'}},
  "cappyzawa/trim.nvim",
  "numToStr/Comment.nvim",
  "dstein64/nvim-scrollview",
  "lewis6991/gitsigns.nvim",
  "mhartington/formatter.nvim",
  {"nvim-treesitter/nvim-treesitter", build=":TSUpdate"},
  "zbirenbaum/copilot.lua",
  {"nvim-telescope/telescope.nvim", dependencies={"nvim-lua/plenary.nvim"}},
  "neovim/nvim-lspconfig",
})

require("onedark").load()          -- Load One Dark theme
require("lualine").setup()         -- Lualine setup
require("trim").setup()            -- Trim setup
require("Comment").setup()         -- Comment setup
require("scrollview").setup()      -- Scrollview setup
require("gitsigns").setup()        -- Gitsigns setup
require("formatter").setup()       -- Formatter setup
require("nvim-treesitter.configs").setup({ -- Treesitter setup
  ensure_installed = "all",
  highlight = { enable = true },
  indent = { enable = true },
})
require("copilot").setup(          -- Copilot options
  { suggestion = { auto_trigger = true, keymap = { accept = "<M-Tab>" } } }
)                                  -- Set up language servers
-- require("lspconfig").solargraph.setup()

                                   -- Telescope keybindings
local telescope = require('telescope.builtin')
vim.keymap.set('n', '<leader>.', telescope.find_files, {})
vim.keymap.set('n', '<leader>/', telescope.live_grep, {})
vim.keymap.set('n', '<leader>ff', telescope.find_files, {})
vim.keymap.set('n', '<leader>fg', telescope.live_grep, {})
vim.keymap.set('n', '<leader>fb', telescope.buffers, {})
vim.keymap.set('n', '<leader>fh', telescope.help_tags, {})
