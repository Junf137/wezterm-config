-- Run with: wezterm --config-file tests/window-defaults.lua show-keys --lua
-- Load the complete configuration and reject automatic window-state hooks.
local wezterm = require('wezterm')
local root = wezterm.config_dir .. '/..'
package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. package.path

local original_on = wezterm.on
wezterm.on = function(event, callback)
   assert(event ~= 'gui-startup' and event ~= 'gui-attached',
      'New windows should use normal startup, without forced maximize/fullscreen')
   return original_on(event, callback)
end

local config = dofile(root .. '/wezterm.lua')
assert(config.window_decorations == 'RESIZE', 'Resize borders must work on every platform')

local platform = require('utils.platform')
local expected_leader = platform.is_mac and 'CTRL|ALT' or 'ALT|CTRL'
assert(config.leader.mods == expected_leader, 'Unexpected platform leader shortcut')

return config
