local wezterm = require('wezterm')
local platform = require('utils.platform')

local M = {}

local SOUND_FILE = {
   linux = '/usr/share/sounds/freedesktop/stereo/bell.oga',
   mac = '/System/Library/Sounds/Ping.aiff',
}

-- Linux volume: 65536 = 100%. Values above 65536 boost beyond normal volume.
-- macOS volume: 0.0-1.0 (afplay -v).
local VOLUME = {
   linux = 98304, -- 150%
   mac = 1.0,
}

local function play_cmd(file)
   if platform.is_linux then
      return { 'paplay', '--volume', tostring(VOLUME.linux), file }
   elseif platform.is_mac then
      return { 'afplay', '-v', tostring(VOLUME.mac), file }
   end
   return nil
end

M.setup = function()
   wezterm.on('bell', function(window, pane)
      local file = SOUND_FILE[platform.os]
      if not file then return end
      local cmd = play_cmd(file)
      if cmd then
         wezterm.background_child_process(cmd)
      end
   end)
end

return M
