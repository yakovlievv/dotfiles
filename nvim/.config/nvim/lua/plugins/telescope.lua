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
          -- Configure ripgrep to include hidden files but ignore the .git directory
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
          file_ignore_patterns = { ".git/" },
          -- Use fd for file searching, including hidden files and excluding .git
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

      -- Set key mappings after telescope has been configured
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
    end,
  },
}

