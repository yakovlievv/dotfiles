return {
  "norcalli/nvim-colorizer.lua",
  config = function()
    require("colorizer").setup({
      "*", -- highlight all files
      css = { rgb_fn = true }, -- enable parsing rgb(...) functions in css/scss files
      scss = { rgb_fn = true },
      html = { names = false }, -- disable named colors in html
    })
  end,
}
