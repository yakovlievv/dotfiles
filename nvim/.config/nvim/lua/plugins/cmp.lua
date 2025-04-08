return {
    'hrsh7th/nvim-cmp',
    dependencies = {
        {
            'L3MON4D3/LuaSnip',
            build = "make install_jsregexp",
            dependencies = {
                {
                    'rafamadriz/friendly-snippets',
                    config = function()
                        require('luasnip.loaders.from_vscode').lazy_load()
                    end,
                },
            },
            'onsails/lspkind.nvim',
            'saadparwaiz1/cmp_luasnip',
            'hrsh7th/cmp-nvim-lsp',
            'hrsh7th/cmp-path',
            'hrsh7th/cmp-buffer',
        },
    },
    config = function()
        local cmp = require'cmp'
        local luasnip = require('luasnip')
        local lspkind = require('lspkind')
        local types = require("luasnip.util.types")

        -- Configure LuaSnip without calling setup() redundantly.
        luasnip.config.set_config({
            history = true,
            updateevents = "TextChanged,TextChangedI",
            ext_opts = {
                [types.choiceNode] = {
                    active = {
                        virt_text = {{"", "DiagnosticHint"}},
                        -- Or if you prefer a highlight style:
                        -- hl_group = "Visual",
                    },
                },
                [types.insertNode] = {
                    active = {
                        virt_text = {{"󰆷", "DiagnosticHint"}},
                        -- hl_group = "Visual",
                    },
                },
            },
        })

        cmp.setup({
            snippet = {
                expand = function(args)
                    luasnip.lsp_expand(args.body)
                end,
            },

            window = {
                completion = cmp.config.window.bordered({
                    max_height = 8,
                }),

                documentation = cmp.config.window.bordered({
                    max_height = 8,
                    max_width = 20,  -- Fixed width (corrected)
                    min_width = 10,  -- Fixed width (corrected)
                }),
            },
            mapping = cmp.mapping.preset.insert({
                ['<C-b>'] = cmp.mapping.scroll_docs(-4),
                ['<C-f>'] = cmp.mapping.scroll_docs(4),
                ['<C-n>'] = cmp.mapping.select_next_item(),
                ['<C-p>'] = cmp.mapping.select_prev_item(),
                ['<C-m>'] = cmp.mapping.complete(),
                ['<C-y>'] = cmp.mapping.confirm({
                    select = true,
                    behavior = cmp.ConfirmBehavior.Insert,
                }),
                ['<C-l>'] = cmp.mapping(function()
                    if luasnip.expand_or_locally_jumpable() then
                        luasnip.expand_or_jump()
                    end
                end, { 'i', 's' }),
                ['<C-h>'] = cmp.mapping(function()
                    if luasnip.locally_jumpable(-1) then
                        luasnip.jump(-1)
                    end
                end, { 'i', 's' }),
            }),

            sources = cmp.config.sources({
                { name = 'nvim_lsp', max_item_count = 5 },
                { name = 'luasnip', max_item_count = 5 },
            }, {
                { name = 'path', max_item_count = 5 },
                { name = 'buffer', keyword_length = 4, max_item_count = 5 },
            }),

            formatting = {
                format = lspkind.cmp_format({
                    mode = 'symbol_text',
                    maxwidth = 50,
                    ellipsis_char = '...',
                    show_labelDetails = true,
                })
            },
            sorting = {
                comparators = {
                    function(entry1, entry2)
                        local cursor = vim.api.nvim_win_get_cursor(0)
                        local current_line = vim.api.nvim_get_current_line()
                        local typed = current_line:sub(1, cursor[2] + 1):match("%S+$") or ""
                        local label1 = entry1.completion_item.label:lower()
                        local label2 = entry2.completion_item.label:lower()
                        local match1 = label1:find("^" .. vim.pesc(typed:lower()))
                        local match2 = label2:find("^" .. vim.pesc(typed:lower()))
                        if match1 and not match2 then
                            return true
                        elseif match2 and not match1 then
                            return false
                        end
                    end,
                    cmp.config.compare.score,
                    cmp.config.compare.recently_used,
                    cmp.config.compare.offset,
                    cmp.config.compare.order,
                },
            },
        })

        -- Uncomment cmdline setups as needed.
        -- cmp.setup.cmdline('/', { mapping = cmp.mapping.preset.cmdline(), sources = { { name = 'buffer' } } })
        -- cmp.setup.cmdline(':', {
        --     mapping = cmp.mapping.preset.cmdline(),
        --     sources = cmp.config.sources({ { name = 'path' } }, { { name = 'cmdline' } }),
        --     matching = { disallow_symbol_nonprefix_matching = false },
        -- })
    end,
}

