local wezterm = require("wezterm")

local config = {}

config.color_scheme = "Catppuccin Mocha"

config.font = wezterm.font("JetBrainsMono Nerd Font Mono")
config.font_size = 16

-- WINDOW --

-- Opacity
config.window_background_opacity = 0.9
config.macos_window_background_blur = 10
config.adjust_window_size_when_changing_font_size = false


config.colors = {
    background = "#11111b", -- any hex color
}

config.window_decorations = "RESIZE"
config.window_padding = {
    left = 15,
    right = 15,
    top = 10,
    bottom = 10,
}

-- Cursor
config.default_cursor_style = "BlinkingBlock"
config.cursor_blink_rate = 500

-- Cursor trail – ❌ NOT SUPPORTED
-- No equivalent exists in WezTerm.

-- Ligatures
config.harfbuzz_features = { "calt=1", "clig=1", "liga=1" }

config.enable_tab_bar = false

-- macOS option as alt
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false

-- Shell integration
-- Equivalent of "shell_integration no-cursor" doesn’t exist
-- But you can turn it off completely:
config.enable_wayland = false -- if relevant, no direct "shell integration" toggle

-- Keybindings
config.keys = {
    -- Ctrl + Backspace → send ^W
    {
        key = "Backspace",
        mods = "CTRL",
        action = wezterm.action.SendKey({ key = "w", mods = "CTRL" }),
    },
}

-- Clipboard mappings (commented like yours)
--[[
{
  key = "V",
  mods = "CTRL",
  action = wezterm.action.PasteFrom("Clipboard"),
},
{
  key = "C",
  mods = "CTRL",
  action = wezterm.action.CopyTo("Clipboard"),
},
]]

return config
