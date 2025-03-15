vim.g.mapleader = " "
vim.o.guifont = "JetBrainsMono Nerd Font:h12"
vim.opt.nu = true
vim.opt.relativenumber = true

vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true 

vim.opt.smartindent = true

vim.o.wrap = false

vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.opt.undofile = true

vim.opt.hlsearch = false
vim.opt.incsearch = true

-- Enable true colors
vim.opt.termguicolors = true

-- Function to set transparency properly
--local function set_transparency()
--  -- Make the main editing area stay transparent, even when unfocused
--  local normal_groups = { "Normal", "NormalNC", "NormalFloat", "SignColumn", "NonText" }
--  for _, group in ipairs(normal_groups) do
--    vim.api.nvim_set_hl(0, group, { bg = "none", ctermbg = "none" })
--  end
--
--  -- Ensure Neo-tree stays transparent, but can have a different color
--  local neotree_groups = { "NeoTreeNormal", "NeoTreeNormalNC" }
--  for _, group in ipairs(neotree_groups) do
--    vim.api.nvim_set_hl(0, group, { bg = "none", ctermbg = "none" }) -- Change "none" to a hex color if you want a tint
--  end
--end
--
---- Apply transparency on startup
--set_transparency()
--
---- Make sure transparency stays when changing colorschemes
--vim.api.nvim_create_autocmd("ColorScheme", {
--  pattern = "*",
--  callback = function()
--    vim.defer_fn(set_transparency, 0) -- Defer to prevent colorscheme override
--  end,
--})


vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.isfname:append("@-@")

vim.opt.updatetime = 50
vim.opt.colorcolumn = "80"

