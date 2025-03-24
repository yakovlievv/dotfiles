return {
    {
        "nvim-telescope/telescope.nvim",
        tag = "0.1.8", -- or use branch = "0.1.x"
        dependencies = {
            "nvim-lua/plenary.nvim",
            "BurntSushi/ripgrep",
            "sharkdp/fd",
        },
        config = function()
            require("telescope").setup({
                defaults = {
                    -- Configure ripgrep to include hidden files but ignore .git directory
                    vimgrep_arguments = {
                        "rg",
                        "--color=never",
                        "--no-heading",
                        "--with-filename",
                        "--line-number",
                        "--column",
                        "--smart-case",
                        "--hidden",
                        "--glob",
                        "!.git/*",
                    },
                    -- Telescope's own ignore pattern (if needed)
                    file_ignore_patterns = { ".git/" },
                    -- Use fd for file searching, include hidden files and exclude .git
                    find_command = { "fd", "--type", "f", "--strip-cwd-prefix", "--hidden", "--exclude", ".git", "--no-ignore" },
                },
                pickers = {
                    find_files = {
                        hidden = true,
                        no_ignore = true,
                    },
                    live_grep = {
                        additional_args = function()
                            return { "--hidden", "--glob", "!.git/*" }
                        end,
                    },
                },
            })
        end,
    },
}
