local wezterm = require('wezterm')
local mux = wezterm.mux
local platform = require('utils.platform')

local M = {}

M.setup = function()
   wezterm.on('gui-startup', function(cmd)
      local _, _, window = mux.spawn_window(cmd or {})
      local gui_window = window:gui_window()
      
      if platform.is_mac then
         -- On macOS, toggle_fullscreen works more reliably than maximize
         gui_window:toggle_fullscreen()
      else
         -- On Linux and Windows, maximize works fine
         gui_window:maximize()
      end
   end)
end

return M
