return {
	"folke/noice.nvim",
	event = "VeryLazy",
	opts = {},
	dependencies = {
		"MunifTanjim/nui.nvim",
        "hrsh7th/nvim-cmp",
        "hrsh7th/cmp-cmdline",
	},
	config = function()
		require("noice").setup({
			lsp = {
				override = {
					["vim.lsp.util.convert_input_to_markdown_lines"] = true,
					["vim.lsp.util.stylize_markdown"] = true,
					["cmp.entry.get_documentation"] = true, -- requires hrsh7th/nvim-cmp
				},
			},
			-- enable presets for easier configuration
			presets = {
				bottom_search = true,      -- use a classic bottom cmdline for search
				command_palette = true,    -- position the cmdline and popupmenu together
				long_message_to_split = true,  -- long messages will be sent to a split
				inc_rename = false,        -- enables an input dialog for inc-rename.nvim
				lsp_doc_border = true,    -- add a border to hover docs and signature help
			},
			-- Use a minimal view for messages to avoid distractions
			messages = {
				view = "mini",
			},
			-- Optionally, filter out messages that you don't need to see at all
			routes = {
				{
					filter = { event = "msg_show", kind = "" },
					opts = { skip = true },
				},
			},
		})
	end,
}

