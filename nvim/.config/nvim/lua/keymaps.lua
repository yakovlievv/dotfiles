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

-- FIND/REPLACE: Search and replace the word under the cursor globally
vim.keymap.set("n", "<leader>s", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]])

-- QUTING VIM
vim.keymap.set("n", "<leader>q", [[:qa!<CR>]])
vim.keymap.set("n", "<leader>Q", [[:wqa!<CR>]])

-- END/START OF THE LINE
vim.keymap.set('n', 'H', '_')
vim.keymap.set('n', 'L', '$')
