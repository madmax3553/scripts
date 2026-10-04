#!/usr/bin/env bash
#  ▄████  ██▀███   ▒█████   ▒█████  ▄▄▄█████▓
# ██▒ ▀█▒▓██ ▒ ██▒▒██▒  ██▒▒██▒  ██▒▓  ██▒ ▓▒
#▒██░▄▄▄░▓██ ░▄█ ▒▒██░  ██▒▒██░  ██▒▒ ▓██░ ▒░
#░▓█  ██▓▒██▀▀█▄  ▒██   ██░▒██   ██░░ ▓██▓ ░
#░▒▓███▀▒░██▓ ▒██▒░ ████▓▒░░ ████▓▒░  ▒██▒ ░
# ░▒   ▒ ░ ▒▓ ░▒▓░░ ▒░▒░▒░ ░ ▒░▒░▒░   ▒ ░░
#  ░   ░   ░▒ ░ ▒░  ░ ▒ ▒░   ░ ▒ ▒░     ░
#░ ░   ░   ░░   ░ ░ ░ ░ ▒  ░ ░ ░ ▒    ░
#      ░    ░         ░ ░      ░ ░
# Script: keybindings.sh
# Purpose: Show grouped Hyprland keybinds in fuzzel and copy a selected entry
# Dependencies: lua, fuzzel, wl-copy
# Author: groot
# Modified: 2026-10-03

set -euo pipefail

# Reads configs/keybinds.lua (the conf file was removed in the Lua migration).
# A stub hl records each bind, including the workspace loop, in source order.

list_keybinds() {
	HYPRLAND_LUA="${HOME}/.config/hypr/hyprland.lua" \
	KEYBINDS_LUA="${HOME}/.config/hypr/configs/keybinds.lua" \
	lua - <<'LUA'
local hyprland_path = os.getenv("HYPRLAND_LUA")
local keybinds_path = os.getenv("KEYBINDS_LUA")

local function read_all(path)
	local f, err = io.open(path, "r")
	if not f then
		io.stderr:write("keybindings: " .. tostring(err) .. "\n")
		os.exit(1)
	end
	local src = f:read("*a")
	f:close()
	return src
end

local function config_string(name, default)
	local src = read_all(hyprland_path)
	local value = src:match("local%s+" .. name .. '%s*=%s*"([^"]*)"')
	if value and value ~= "" then
		return value
	end
	return default
end

local mainMod = config_string("mainMod", "SUPER")
local terminal = config_string("terminal", "ghostty")
local fileManager = config_string("fileManager", "pcmanfm-qt")
local menu = config_string("menu", "~/.local/bin/launcher/launcher.sh")

local function opens_block(line)
	return line:match("^%s*function%s+")
		or line:match("^%s*local%s+function%s+")
		or line:match("^%s*if%s+")
		or line:match("^%s*for%s+")
		or line:match("^%s*while%s+")
end

local section = "General"
local section_queue = {}
local depth = 0
local for_depth = nil
local for_count = 1

for line in io.lines(keybinds_path) do
	local title = line:match("^%s*%-%-%s+([^%s].-)%s*$")
	if title and not title:match("^%-") then
		section = title
	end

	if opens_block(line) then
		depth = depth + 1
		local count = line:match("^%s*for%s+%w+%s*=%s*%d+%s*,%s*(%d+)")
		if count then
			for_depth = depth
			for_count = tonumber(count)
		end
	end

	if line:match("hl%.bind%s*%(") then
		local copies = (for_depth and depth >= for_depth) and for_count or 1
		for _ = 1, copies do
			section_queue[#section_queue + 1] = section
		end
	end

	if line:match("^%s*end%s*$") then
		if for_depth == depth then
			for_depth = nil
		end
		depth = math.max(depth - 1, 0)
	end
end

local function format_key(key)
	local names = {
		["return"] = "Enter",
		left = "Left",
		right = "Right",
		up = "Up",
		down = "Down",
		space = "Space",
		slash = "/",
		TAB = "Tab",
		mouse_up = "WheelUp",
		mouse_down = "WheelDown",
		["mouse:272"] = "MouseLeft",
		["mouse:273"] = "MouseRight",
	}
	if names[key] then
		return names[key]
	end
	if key:match("^XF86") or key:match("^mouse:") then
		return key
	end
	return key:upper()
end

local function format_combo(combo)
	if not combo:find(" + ", 1, true) then
		return format_key(combo)
	end
	local parts = {}
	local rest = combo
	while true do
		local split_at, split_to = rest:find(" + ", 1, true)
		local piece
		if not split_at then
			piece = rest
		else
			piece = rest:sub(1, split_at - 1)
		end
		local mod_names = { SUPER = "Super", CTRL = "Ctrl", SHIFT = "Shift", ALT = "Alt" }
		parts[#parts + 1] = mod_names[piece] or format_key(piece)
		if not split_at then
			break
		end
		rest = rest:sub(split_to + 1)
	end
	return table.concat(parts, "+")
end

local function describe_exec(cmd)
	if cmd == terminal then return "Terminal" end
	if cmd == fileManager then return "File manager" end
	if cmd:find("keybindings.sh", 1, true) then return "Show this keybind list" end
	if cmd:find("window-switcher.sh", 1, true) then return "Window switcher" end
	if cmd:find("ask-gemini.sh", 1, true) or cmd:find("ask-antigravity.sh", 1, true) then
		return "Ask Antigravity"
	end
	if cmd:find("surface-dashboard", 1, true) then return "Journal dashboard" end
	if cmd:find("surface-todo", 1, true) then return "Journal TODO" end
	if cmd:find("scratchpad.sh", 1, true) then return "Scratchpad" end
	if cmd:find("iced.sh ice", 1, true) then return "Ice browser tab" end
	if cmd:find("iced.sh thaw", 1, true) then return "Thaw browser tab" end
	if cmd:find("iced.sh remove", 1, true) then return "Remove iced tab" end
	if cmd:find("passmenu.sh", 1, true) then return "Password menu" end
	if cmd:find("launcher.sh", 1, true) then return "App launcher" end
	if cmd:find("qalculate", 1, true) then return "Calculator" end
	if cmd == "monitor" then return "Monitor layout" end
	if cmd:find("dash-home", 1, true) then return "Focus or launch dashboard" end
	if cmd:find("txtcliphist", 1, true) then return "Clipboard history" end
	if cmd:find("screenshot.sh area", 1, true) then return "Screenshot area" end
	if cmd:find("screenshot.sh window", 1, true) then return "Screenshot window" end
	if cmd:find("screenshot.sh screen", 1, true) then return "Screenshot screen" end
	if cmd:find("pkill waybar", 1, true) then return "Restart Waybar" end
	if cmd == "waytrogen" then return "Wallpaper picker" end
	if cmd:find("perf-toggle", 1, true) then return "Performance mode" end
	if cmd:find("wpctl set-volume", 1, true) and cmd:find("5%+", 1, true) then return "Volume up" end
	if cmd:find("wpctl set-volume", 1, true) then return "Volume down" end
	if cmd:find("DEFAULT_AUDIO_SOURCE", 1, true) then return "Mute microphone" end
	if cmd:find("set-mute", 1, true) then return "Mute audio" end
	if cmd:find("brightnessctl", 1, true) and cmd:find("5%+", 1, true) then return "Brightness up" end
	if cmd:find("brightnessctl", 1, true) then return "Brightness down" end
	if cmd:find("playerctl next", 1, true) then return "Next track" end
	if cmd:find("playerctl previous", 1, true) then return "Previous track" end
	if cmd:find("playerctl play-pause", 1, true) then return "Play/pause" end
	return cmd
end

local function describe(dispatcher)
	if type(dispatcher) ~= "table" or not dispatcher.path then
		return tostring(dispatcher)
	end
	local path = dispatcher.path
	local arg = dispatcher.args and dispatcher.args[1]
	if path == "exec_cmd" then
		return describe_exec(tostring(arg or ""))
	elseif path == "window.close" then
		return "Close window"
	elseif path == "window.float" then
		return "Toggle floating"
	elseif path == "window.pseudo" then
		return "Toggle pseudotile"
	elseif path == "layout" then
		return "Toggle split orientation"
	elseif path == "window.fullscreen" then
		local mode = type(arg) == "table" and arg.mode or "fullscreen"
		if mode == "maximized" then
			return "Toggle maximized"
		end
		return "Toggle fullscreen"
	elseif path == "window.drag" then
		return "Drag window"
	elseif path == "window.resize" then
		return "Resize window"
	elseif path == "window.move" then
		local ws = type(arg) == "table" and tostring(arg.workspace or "") or ""
		if ws:find("special:", 1, true) == 1 then
			return "Move window to special workspace " .. ws:sub(#"special:" + 1)
		end
		return "Move window to workspace " .. ws
	elseif path == "focus" then
		if type(arg) == "table" and arg.direction then
			local names = { l = "left", r = "right", u = "up", d = "down" }
			return "Focus " .. (names[arg.direction] or arg.direction)
		end
		if type(arg) == "table" and arg.workspace then
			local ws = tostring(arg.workspace)
			if ws == "e+1" then return "Next workspace" end
			if ws == "e-1" then return "Previous workspace" end
			return "Focus workspace " .. ws
		end
	elseif path == "workspace.toggle_special" then
		return "Toggle special workspace " .. tostring(arg or "")
	end
	return path
end

local function dsp_node(path)
	return setmetatable({}, {
		__index = function(_, key)
			local next_path = path == "" and key or (path .. "." .. key)
			return dsp_node(next_path)
		end,
		__call = function(_, ...)
			return { path = path, args = { ... } }
		end,
	})
end

local bind_i = 0
local last_section = nil
hl = {
	bind = function(combo, dispatcher, _)
		bind_i = bind_i + 1
		local group = section_queue[bind_i] or "General"
		if group ~= last_section then
			io.write(string.format("__section__\t[%s]\n", group))
			last_section = group
		end
		io.write(string.format("%s\t%-24s %s\n", group, format_combo(tostring(combo)), describe(dispatcher)))
	end,
	dsp = dsp_node(""),
}

local chunk, load_err = loadfile(keybinds_path)
if not chunk then
	io.stderr:write("keybindings: " .. tostring(load_err) .. "\n")
	os.exit(1)
end

local setup = chunk()
if type(setup) ~= "function" then
	io.stderr:write("keybindings: keybinds.lua did not return a setup function\n")
	os.exit(1)
end

local ok, exec_err = pcall(setup, {
	mainMod = mainMod,
	terminal = terminal,
	fileManager = fileManager,
	menu = menu,
})
if not ok then
	io.stderr:write("keybindings: " .. tostring(exec_err) .. "\n")
	os.exit(1)
end

if bind_i ~= #section_queue then
	io.stderr:write(string.format(
		"keybindings: grouped %d binds, config emitted %d\n",
		#section_queue,
		bind_i
	))
end
LUA
}

if [[ "${1:-}" == "--dump" ]]; then
	list_keybinds | cut -f2-
	exit 0
fi

if ! output=$(list_keybinds); then
	if command -v notify-send >/dev/null 2>&1; then
		notify-send -u critical "Keybindings" "Could not read Hyprland keybinds"
	fi
	exit 1
fi

selection=$(printf '%s\n' "$output" | cut -f2- | fuzzel --dmenu --prompt 'Keys> ' --width 90 --lines 24) || exit 0

[[ -z "$selection" || $selection =~ ^\[.*\]$ ]] && exit 0

printf '%s' "$selection" | wl-copy
