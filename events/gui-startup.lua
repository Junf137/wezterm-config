local wezterm = require('wezterm')
local mux = wezterm.mux

local M = {}

M.setup = function()
   wezterm.on('gui-startup', function(cmd)
      local _, _, window = mux.spawn_window(cmd or {})
      -- Maximize fills the screen as a normal window; not macOS fullscreen.
      window:gui_window():maximize()
   end)
end

return M
