return {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-tree/nvim-web-devicons",
        "MunifTanjim/nui.nvim",
    },
    config = function()
        require("neo-tree").setup({
            filesystem = {
                filtered_items = {
                    visible = true,
                    hide_dotfiles = false,
                    hide_gitignored = false,
                    use_popups = false,
                },
            },
            window = {
                width = 30,  -- Adjust the width to your preference
                mappings = {
                    ["q"] = "close_window",  -- Press 'q' inside neo-tree to close the panel
                },
            },
        })
    end,
}
