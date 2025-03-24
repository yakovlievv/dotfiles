return {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
        local config = require("nvim-treesitter.configs")
        config.setup({
            auto_install = true,
            highlight = {
                enable = true, -- Fix the typo here
                additional_vim_regex_highlighting = false,
            },
            indent = { enable = true },
            playground = { enable = true },
        })
    end
}

