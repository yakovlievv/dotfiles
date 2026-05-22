-------------------
---- VARIABLES ----
-------------------

local programs = {
	terminal = "kitty",
	fileManager = "thunar",
	browser = "zen-browser",
}

------------------
---- REQUIRED ----
------------------

require("keybinds")(programs)
local colors = require("mocha")

-----------------
---- MONITOR ----
-----------------

hl.monitor({
	output = "",
	mode = "preferred",
	position = "auto",
	scale = "1.33",
})

-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
	hl.exec_cmd("waybar & hyprpaper & syncthing --no-browser & xsettingsd")
	hl.exec_cmd("hyprctl setcursor theme Bibata-Modern-Classic 24")
	hl.exec_cmd("AyuGram")
	hl.exec_cmd("emacs --daemon")
end)

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

hl.env("GTK_THEME", "Catppuccin-Mocha-Lavender")

hl.env("HYPRCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Classic")

hl.env("XCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")

-----------------------
----- PERMISSIONS -----
-----------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Permissions/
-- Please note permission changes here require a Hyprland restart and are not applied on-the-fly
-- for security reasons

-- hl.config({
--   ecosystem = {
--     enforce_permissions = true,
--   },
-- })

-- hl.permission("/usr/(bin|local/bin)/grim", "screencopy", "allow")
-- hl.permission("/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland", "screencopy", "allow")
-- hl.permission("/usr/(bin|local/bin)/hyprpm", "plugin", "allow")

-----------------------
---- LOOK AND FEEL ----
-----------------------

-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/
hl.config({
	general = {
		gaps_in = 4,
		gaps_out = 7,

		border_size = 0,

		col = {
			-- active_border = colors.lavender,
			-- inactive_border = colors.base,
		},

		resize_on_border = false,

		allow_tearing = false,

		layout = "dwindle",
	},

	decoration = {
		rounding = 10,
		rounding_power = 2,

		-- Change transparency of focused and unfocused windows
		active_opacity = 1.0,
		inactive_opacity = 1,

		shadow = {
			enabled = true,
			range = 3,
			render_power = 5,
			color = 0xee1a1a1a,
		},

		blur = {
			enabled = true,
			size = 5,
			passes = 2,
			vibrancy = 0.1696,
		},
	},

	animations = {
		enabled = true,
	},
})

-- Default curves and animations, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })

-- Default springs
hl.curve("easy", { type = "spring", mass = 1, stiffness = 71.2633, dampening = 15.8273644 })

hl.animation({ leaf = "global", enabled = true, speed = 6, bezier = "easeOutQuint" })
hl.animation({ leaf = "border", enabled = true, speed = 4, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows", enabled = true, speed = 3, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 2.5, bezier = "easeOutQuint", style = "popin 90%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2, bezier = "easeOutQuint", style = "popin 90%" })
hl.animation({ leaf = "fade", enabled = true, speed = 2.5, bezier = "quick" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 2, bezier = "quick" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.5, bezier = "quick" })
hl.animation({ leaf = "layers", enabled = true, speed = 3, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 2.5, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 2, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.8, bezier = "quick" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.5, bezier = "quick" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 2, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 1.8, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 2, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "zoomFactor", enabled = true, speed = 5, bezier = "quick" })

-- Ref https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

-- "Smart gaps" / "No gaps when only"
-- uncomment all if you wish to use that.
-- hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
-- hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })
-- hl.window_rule({
--     name  = "no-gaps-wtv1",
--     match = { float = false, workspace = "w[tv1]" },
--     border_size = 0,
--     rounding    = 0,
-- })
-- hl.window_rule({
--     name  = "no-gaps-f1",
--     match = { float = false, workspace = "f[1]" },
--     border_size = 0,
--     rounding    = 0,
-- })

-- See https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/ for more
hl.config({
	dwindle = {
		preserve_split = true, -- You probably want this
	},
})

-- See https://wiki.hypr.land/Configuring/Layouts/Master-Layout/ for more
hl.config({
	master = {
		new_status = "master",
	},
})

-- See https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/ for more
hl.config({
	scrolling = {
		fullscreen_on_one_column = true,
	},
})

hl.config({
	group = {
		groupbar = {
			height = 18,
			rounding = 6,
			gradients = false,
			font_size = 12,
			text_color = colors.text,
			col = {
				active = colors.mauve,
				inactive = colors.surface0,
			},
		},
	},
})

----------------
----  MISC  ----
----------------

hl.config({
	misc = {
		force_default_wallpaper = -1, -- Set to 0 or 1 to disable the anime mascot wallpapers
		disable_hyprland_logo = false, -- If true disables the random hyprland logo / anime girl background. :(
	},
})

---------------
---- INPUT ----
---------------

hl.config({
	input = {
		kb_layout = "us,ua",
		kb_variant = "",
		kb_model = "",
		kb_options = "", -- layout toggle handled by Hyprland bind (F14 from keyd)
		kb_rules = "",
		follow_mouse = 1,
		repeat_delay = 200,
		repeat_rate = 35,
		sensitivity = 0,
		touchpad = {
			natural_scroll = false,
		},
	},
})

hl.gesture({
	fingers = 3,
	direction = "horizontal",
	action = "workspace",
})

-- Example per-device config
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/ for more
hl.device({
	name = "epic-mouse-v1",
	sensitivity = -0.5,
})

--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

-- Example window rules that are useful

local suppressMaximizeRule = hl.window_rule({
	-- Ignore maximize requests from all apps. You'll probably like this.
	name = "suppress-maximize-events",
	match = { class = ".*" },

	suppress_event = "maximize",
})
-- suppressMaximizeRule:set_enabled(false)

hl.window_rule({
	-- Fix some dragging issues with XWayland
	name = "fix-xwayland-drags",
	match = {
		class = "^$",
		title = "^$",
		xwayland = true,
		float = true,
		fullscreen = false,
		pin = false,
	},

	no_focus = true,
})

-- Layer rules also return a handle.
-- local overlayLayerRule = hl.layer_rule({
--     name  = "no-anim-overlay",
--     match = { namespace = "^my-overlay$" },
--     no_anim = true,
-- })
-- overlayLayerRule:set_enabled(false)

-- Hyprland-run windowrule
hl.window_rule({
	name = "move-hyprland-run",
	match = { class = "hyprland-run" },

	move = "20 monitor_h-120",
	float = true,
})

hl.workspace_rule({ workspace = "special:ayugram", gaps_out = 20 })

hl.window_rule({
	name = "ayugram-scratchpad",
	match = { title = "AyuGram" },
	workspace = "special:ayugram silent",
})

hl.window_rule({
	name = "thunar-float",
	match = { class = "thunar" },

	float = true,
})

hl.window_rule({
	name = "floating-border",
	match = { float = true },

	border_size = 3,
})
