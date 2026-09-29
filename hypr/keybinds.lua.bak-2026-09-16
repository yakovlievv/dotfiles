---@diagnostic disable: undefined-global

return function(programs)
	local terminal = programs.terminal
	local fileManager = programs.fileManager
	local browser = programs.browser

	local mainMod = "SUPER"

	-- WINDOW CONTOROLS --

	---@diagnostic disable-next-line: unused-local
	local closeWindowBind = hl.bind(mainMod .. " + Q", hl.dsp.window.close())
	hl.bind(mainMod .. " + CTRL + Q", hl.dsp.window.kill())

	hl.bind(mainMod .. " + h", hl.dsp.focus({ direction = "left" }))
	hl.bind(mainMod .. " + l", hl.dsp.focus({ direction = "right" }))
	hl.bind(mainMod .. " + k", hl.dsp.focus({ direction = "up" }))
	hl.bind(mainMod .. " + j", hl.dsp.focus({ direction = "down" }))

	hl.bind(mainMod .. " + SHIFT + L", hl.dsp.window.move({ direction = "right" }))
	hl.bind(mainMod .. " + SHIFT + H", hl.dsp.window.move({ direction = "left" }))
	hl.bind(mainMod .. " + SHIFT + J", hl.dsp.window.move({ direction = "down" }))
	hl.bind(mainMod .. " + SHIFT + K", hl.dsp.window.move({ direction = "up" }))

	hl.bind(mainMod .. " + CTRL + L", hl.dsp.window.resize({ x = 20, y = 0, relative = true }), { repeating = true })
	hl.bind(mainMod .. " + CTRL + H", hl.dsp.window.resize({ x = -20, y = 0, relative = true }), { repeating = true })

	hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
	hl.bind(mainMod .. " + CTRL + F", hl.dsp.window.fullscreen())
	hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
	hl.bind(mainMod .. " + I", hl.dsp.layout("togglesplit")) -- dwindle only
	hl.bind(mainMod .. " + G", hl.dsp.group.toggle())
	hl.bind(mainMod .. " + Tab", hl.dsp.group.next())

	-- Switch workspaces with mainMod + [0-9]
	-- Move active window to a workspace with mainMod + SHIFT + [0-9]
	for i = 1, 10 do
		local key = i % 10 -- 10 maps to key 0
		hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
		hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
	end

	-- PROGRAMS --

	hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
	hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser))
	hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("emacsclient -c"))
	hl.bind(mainMod .. " + F", hl.dsp.exec_cmd(fileManager))
	hl.bind(mainMod .. " + Space", hl.dsp.exec_cmd("rofi -show combi"))

	hl.bind(mainMod .. " + T", hl.dsp.workspace.toggle_special("ayugram"))

	-- UTILITIES --
	hl.bind(
		mainMod .. " + S",
		hl.dsp.exec_cmd(
			'grim -g "$(slurp -b 1e1e2eaa -c cba6f7ff -s 00000000 -w 2)" - | tee ~/Pictures/screenshots/$(date +%Y-%m-%d_%H-%M-%S).png | wl-copy'
		)
	)
	-- SYSTEM MANIPULATION --

	-- Logout
	hl.bind(
		mainMod .. " + M",
		hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'")
	)

	hl.bind(mainMod .. " + CTRL + S", hl.dsp.exec_cmd("shutdown now"))

	-- MOUSE CONTROLS --

	-- Scroll through existing workspaces with mainMod + scroll
	hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
	hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

	-- Move/resize windows with mainMod + LMB/RMB and dragging
	hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
	hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

	-- LAPTOP MULTI --
	hl.bind(
		"XF86AudioRaiseVolume",
		hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"),
		{ locked = true, repeating = true }
	)
	hl.bind(
		"XF86AudioLowerVolume",
		hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
		{ locked = true, repeating = true }
	)
	hl.bind(
		"XF86AudioMute",
		hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
		{ locked = true, repeating = true }
	)
	hl.bind(
		"XF86AudioMicMute",
		hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
		{ locked = true, repeating = true }
	)
	hl.bind(
		"XF86MonBrightnessUp",
		hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),
		{ locked = true, repeating = true }
	)
	hl.bind(
		"XF86MonBrightnessDown",
		hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),
		{ locked = true, repeating = true }
	)

	-- Requires playerctl
	hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
	hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
	hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
	hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

	-- MISC --

	-- Keyboard layout switch: Left Ctrl (keyd remaps to F14; hold-Ctrl comes from Caps)
	hl.bind("code:192", hl.dsp.exec_cmd("hyprctl switchxkblayout all next"))
end
