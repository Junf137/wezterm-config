-- Run with: wezterm --config-file tests/window-defaults.lua show-keys | sed -n 1p
-- (prints the Leader line only when every assertion passed; see README.md "Check")
-- Load the complete configuration and verify startup without opening a window.
local wezterm = require('wezterm')
local root = wezterm.config_dir .. '/..'
package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. package.path

local original_on = wezterm.on
local startup
wezterm.on = function(event, callback)
   if event == 'gui-startup' then
      assert(not startup, 'Only one startup handler should spawn the initial window')
      startup = callback
   end
   return original_on(event, callback)
end

local config = dofile(root .. '/wezterm.lua')
wezterm.on = original_on
assert(startup, 'The startup handler must be registered')

local original_spawn = wezterm.mux.spawn_window
local spawned, maximized, received = 0, 0, nil
wezterm.mux.spawn_window = function(cmd)
   spawned, received = spawned + 1, cmd
   return nil, nil, {
      gui_window = function()
         return { maximize = function() maximized = maximized + 1 end }
      end,
   }
end

startup(nil)
assert(type(received) == 'table' and next(received) == nil, 'Default startup must use empty options')
local command = { args = { 'sh' }, cwd = wezterm.home_dir }
startup(command)
assert(received == command, 'Explicit startup commands must be preserved')
assert(spawned == 2 and maximized == 2, 'Every startup must spawn and maximize exactly one window')
wezterm.mux.spawn_window = original_spawn

assert(config.window_decorations == 'RESIZE', 'Resize borders must work on every platform')

assert(config.leader.mods == 'CTRL|ALT', 'The leader must be Ctrl+Alt+Space on every platform')

return config
