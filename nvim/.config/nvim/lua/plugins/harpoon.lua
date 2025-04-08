return {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
        local harpoon = require("harpoon")
        harpoon:setup()

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
}
