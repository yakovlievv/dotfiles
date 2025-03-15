-- Neovim Keymaps Configuration

-------------------------------
-- MODULES & REQUIREMENTS
-------------------------------
local builtin = require('telescope.builtin')

local harpoon_ok, harpoon = pcall(require, 'harpoon')
if not harpoon_ok then
  print("Harpoon not installed!")
end

local automaton_ok, cellular_automaton = pcall(require, 'cellular-automaton')
if not automaton_ok then
  print("Cellular Automaton not installed!")
end

-------------------------------
-- UNDO TREE
-------------------------------
vim.keymap.set('n', '<leader>u', vim.cmd.UndotreeToggle)

-------------------------------
-- TELESCOPE
-------------------------------
vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
vim.keymap.set('n', '<leader>fg', builtin.live_grep, {})

-------------------------------
-- NEOTREE
-------------------------------
vim.keymap.set('n', '<leader>n', ':Neotree filesystem reveal left<CR>', {})
vim.keymap.set("n", "<leader>m", ":Neotree close<CR>", { silent = true })

-------------------------------
-- HARPOON
-------------------------------
if harpoon_ok then
  -- Add file to Harpoon list and toggle quick menu
  vim.keymap.set("n", "<leader>a", function() harpoon:list():add() end)
  vim.keymap.set("n", "<leader>e", function() harpoon.ui:toggle_quick_menu(harpoon:list()) end)

  -- Directly select a Harpoon mark (1-4)
  vim.keymap.set("n", "<leader>h", function() harpoon:list():select(1) end)
  vim.keymap.set("n", "<leader>j", function() harpoon:list():select(2) end)
  vim.keymap.set("n", "<leader>k", function() harpoon:list():select(3) end)
  vim.keymap.set("n", "<leader>l", function() harpoon:list():select(4) end)

  -- Navigate previous/next within Harpoon list (reassigned to avoid conflict)
  vim.keymap.set("n", "<leader>gp", function() harpoon:list():prev() end)
  vim.keymap.set("n", "<leader>gn", function() harpoon:list():next() end)
end

-------------------------------
-- LSP
-------------------------------
vim.keymap.set("n", "<leader>zig", "<cmd>LspRestart<cr>")
vim.keymap.set("n", "<leader>f", vim.lsp.buf.format)

-------------------------------
-- GENERAL EDITOR
-------------------------------
-- NORMAL MODE
vim.keymap.set({ "i", "v", "s", "t" }, "<C-Space>", "<Esc>", { noremap = true, silent = true })

-- LINE MOVEMENT (Visual Mode)
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

-- CURSOR CENTERING (Normal Mode)
vim.keymap.set("n", "J", "mzJ`z")
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")
vim.keymap.set("n", "=ap", "ma=ap'a")

-- CLIPBOARD OPERATIONS
vim.keymap.set("x", "<leader>p", [["_dP]])
vim.keymap.set({"n", "v"}, "<leader>y", [["+y]])
vim.keymap.set("n", "<leader>Y", [["+Y]])
vim.keymap.set({"n", "v"}, "<leader>d", "\"_d")

-- DISABLE UNUSED/MISFIRING COMMANDS
vim.keymap.set("n", "Q", "<nop>")

-- TMUX INTEGRATION
vim.keymap.set("n", "<C-f>", "<cmd>silent !tmux neww tmux-sessionizer<CR>")

-- FIND/REPLACE: Search and replace the word under the cursor globally
vim.keymap.set("n", "<leader>s", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]])

-- MAKE FILE EXECUTABLE
vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true })

-------------------------------
-- ERROR HANDLING SNIPPETS (Go)
-------------------------------
vim.keymap.set("n", "<leader>ee", "oif err != nil {<CR>}<Esc>Oreturn err<Esc>")
vim.keymap.set("n", "<leader>ea", "oassert.NoError(err, \"\")<Esc>F\";a")
vim.keymap.set("n", "<leader>ef", "oif err != nil {<CR>}<Esc>Olog.Fatalf(\"error: %s\\n\", err.Error())<Esc>jj")
vim.keymap.set("n", "<leader>el", "oif err != nil {<CR>}<Esc>O.logger.Error(\"error\", \"error\", err)<Esc>F.;i")

-------------------------------
-- FUN & UTILITIES
-------------------------------
-- Cellular Automaton Animation
if automaton_ok then
  vim.keymap.set("n", "<leader>ca", function()
      cellular_automaton.start_animation("make_it_rain")
  end)
end

-- Reload current file (source it)
vim.keymap.set("n", "<leader><leader>", function()
    vim.cmd("so")
end)

