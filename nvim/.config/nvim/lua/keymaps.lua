-- Neovim Keymaps Configuration
-------------------------------
-- MODULES & REQUIREMENTS
-------------------------------
local harpoon_ok, harpoon = pcall(require, "harpoon")
local automaton_ok, cellular_automaton = pcall(require, "cellular-automaton")

-------------------------------
-- VIM FUGITIVE
-------------------------------
vim.keymap.set("n", "<leader>gs", vim.cmd.Git)

-------------------------------
-- UNDO TREE
-------------------------------
vim.keymap.set("n", "<leader>u", vim.cmd.UndotreeToggle)

-------------------------------
-- TELESCOPE
-------------------------------
local builtin = require("telescope.builtin")
vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Telescope find files" })
vim.keymap.set("n", "<leader>fG", builtin.live_grep, { desc = "Telescope live grep" })
vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "Telescope buffers" })
vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Telescope help tags" })
vim.keymap.set("n", "<leader>fc", builtin.command_history)
vim.keymap.set("n", "<leader>fC", builtin.colorscheme)
vim.keymap.set("n", "<leader>fd", builtin.diagnostics)
vim.keymap.set("n", "<leader>fgc", builtin.git_commits)
vim.keymap.set("n", "<leader>fgb", builtin.git_branches)
vim.keymap.set("n", "<leader>fgs", builtin.git_status)
vim.keymap.set("n", "<leader>fga", builtin.git_stash)

-------------------------------
-- NEOTREE
-------------------------------
vim.keymap.set("n", "<leader>ee", ":Neotree filesystem reveal left<CR>", {})
vim.keymap.set("n", "<leader>ec", ":Neotree close<CR>", { silent = true })
 
-------------------------------
-- HARPOON
-------------------------------
if harpoon_ok then
    -- Add file to Harpoon list and toggle quick menu
    vim.keymap.set("n", "<leader>aa", function()
        harpoon:list():add()
    end)
    vim.keymap.set("n", "<leader>ae", function()
        harpoon.ui:toggle_quick_menu(harpoon:list())
    end)

    -- Directly select a Harpoon mark (1-4)
    vim.keymap.set("n", "<leader>h", function()
        harpoon:list():select(1)
    end)
    vim.keymap.set("n", "<leader>j", function()
        harpoon:list():select(2)
    end)
    vim.keymap.set("n", "<leader>k", function()
        harpoon:list():select(3)
    end)
    vim.keymap.set("n", "<leader>l", function()
        harpoon:list():select(4)
    end)

    vim.keymap.set("n", "<leader>gp", function()
        harpoon:list():prev()
    end)
    vim.keymap.set("n", "<leader>gn", function()
        harpoon:list():next()
    end)
end

-------------------------------
-- LSP
-------------------------------
vim.keymap.set("n", "<leader>zig", "<cmd>LspRestart<cr>")
-- vim.keymap.set("n", "<leader>f", vim.lsp.buf.format)
--
-------------------------------
-- GENERAL EDITOR
-------------------------------
-- NORMAL MODE
vim.keymap.set({ 'i', 'c', 't' }, '<C-Space>', '<Esc>', { noremap = true, silent = true })

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
vim.keymap.set({ "n", "v" }, "<leader>y", [["+y]])
vim.keymap.set({ "n", "v" }, "<leader>d", '"_d')
vim.keymap.set("n", "<leader>Y", [["+Y]])

-- DISABLE UNUSED/MISFIRING COMMANDS
vim.keymap.set("n", "Q", "<nop>")

-- TMUX INTEGRATION
-- vim.keymap.set("n", "<C-f>", "<cmd>silent !tmux neww tmux-sessionizer<CR>")

-- FIND/REPLACE: Search and replace the word under the cursor globally
vim.keymap.set("n", "<leader>s", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]])

-- MAKE FILE EXECUTABLE
-- vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true })

-------------------------------
-- FUN & UTILITIES
-------------------------------
-- Cellular Automaton Animation
if automaton_ok then
    vim.keymap.set("n", "<leader>cr", function()
        cellular_automaton.start_animation("make_it_rain")
    end)
end

-- -- Reload current file (source it)
-- vim.keymap.set("n", "<leader><leader>", function()
-- 	vim.cmd("so")
-- end)
