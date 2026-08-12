local wezterm = require('wezterm')
local platform = require('utils.platform')
local backdrops = require('utils.backdrops')
local act = wezterm.action

local mod = {}

if platform.is_mac then
   mod.SUPER = 'SUPER'
   mod.SUPER_REV = 'SUPER|CTRL'
   -- Deliberately not SUPER_REV: SUPER|CTRL Space is the key equivalent of the
   -- Edit > "Emoji & Symbols" menu item that macOS puts in every app's menu bar.
   -- The menu bar consumes it before wezterm's key handling ever runs, so that
   -- leader is dead on macOS -- and it cannot be switched off from
   -- AppleSymbolicHotKeys (id 164 is already disabled and makes no difference),
   -- only by overriding the menu item globally via NSUserKeyEquivalents.
   mod.LEADER = 'SUPER|SHIFT'
elseif platform.is_win or platform.is_linux then
   mod.SUPER = 'ALT' -- to not conflict with Windows key shortcuts
   mod.SUPER_REV = 'ALT|CTRL'
   mod.LEADER = 'ALT|CTRL'
end

-- The tmux the F6 session launcher runs. Always the local one, on whichever machine
-- this config is loaded on. It has to be an absolute path on macOS: wezterm is started
-- there by launchd from Finder/Dock with launchd's own minimal PATH
-- (/usr/bin:/bin:/usr/sbin:/sbin), Homebrew's bin is not on it, and both
-- run_child_process and spawn_tab exec directly rather than through a login shell that
-- would have fixed the PATH up. A bare 'tmux' fails with ENOENT there.
local TMUX = 'tmux'
if platform.is_mac then
   for _, candidate in ipairs({ '/opt/homebrew/bin/tmux', '/usr/local/bin/tmux' }) do
      local probe = io.open(candidate, 'r')
      if probe then
         probe:close()
         TMUX = candidate
         break
      end
   end
end

-- stylua: ignore
---@type Key[]
local keys = {
   -- misc/useful --
   { key = 'F1', mods = 'NONE', action = act.ActivateCopyMode },
   { key = 'F2', mods = 'NONE', action = act.ActivateCommandPalette },
   { key = 'F3', mods = 'NONE', action = act.ShowLauncher },
   { key = 'F4', mods = 'NONE', action = act.ShowLauncherArgs({ flags = 'FUZZY|TABS' }) },
   {
      key = 'F5',
      mods = 'NONE',
      action = act.ShowLauncherArgs({ flags = 'FUZZY|WORKSPACES' }),
   },
   -- Open one tab per local tmux session, enumerated at press-time.
   -- `-A` attaches or creates, so a session that vanished between the listing and the
   -- attach can't fail; `-D` makes it a hard attach, detaching whatever client already
   -- holds the session. That is the point rather than a side effect: two clients on one
   -- session clamp every window to the smaller client's size, so attaching from a
   -- second window without `-D` reshapes the session around the smaller one.
   -- Tab labels come from the pane title, which `set-titles-string` in tmux.conf sets
   -- to `host · #S`.
   {
      key = 'F6',
      mods = 'NONE',
      action = wezterm.action_callback(function(window, _pane)
         local ok, stdout, stderr = wezterm.run_child_process({
            TMUX, 'list-sessions', '-F', '#{session_name}',
         })
         if not ok then
            wezterm.log_error('tmux list-sessions failed: ' .. (stderr or ''))
            window:toast_notification('wezterm', 'no tmux sessions here', nil, 4000)
            return
         end

         local mux_win = window:mux_window()
         for name in stdout:gmatch('[^\n]+') do
            mux_win:spawn_tab({ args = { TMUX, 'new-session', '-A', '-D', '-s', name } })
         end
      end),
   },
   { key = 'F11', mods = 'NONE',    action = act.ToggleFullScreen },
   { key = 'F12', mods = 'NONE',    action = act.ShowDebugOverlay },
   { key = 'f',   mods = mod.SUPER, action = act.Search({ CaseInSensitiveString = '' }) },
   {
      key = 'u',
      mods = mod.SUPER_REV,
      action = wezterm.action.QuickSelectArgs({
         label = 'open url',
         patterns = {
            '\\((https?://\\S+)\\)',
            '\\[(https?://\\S+)\\]',
            '\\{(https?://\\S+)\\}',
            '<(https?://\\S+)>',
            '\\bhttps?://\\S+[)/a-zA-Z0-9-]+'
         },
         action = wezterm.action_callback(function(window, pane)
            local url = window:get_selection_text_for_pane(pane)
            wezterm.log_info('opening: ' .. url)
            wezterm.open_with(url)
         end),
      }),
   },

   -- cursor movement --
   { key = 'LeftArrow',  mods = mod.SUPER,     action = act.SendString('\u{1b}OH') },
   { key = 'RightArrow', mods = mod.SUPER,     action = act.SendString('\u{1b}OF') },

   -- copy/paste --
   { key = 'c',          mods = 'CTRL|SHIFT',  action = act.CopyTo('Clipboard') },
   { key = 'v',          mods = 'CTRL|SHIFT',  action = act.PasteFrom('Clipboard') },

   -- tabs --
   -- tabs: spawn+close
   { key = 't',          mods = mod.SUPER,     action = act.SpawnTab('DefaultDomain') },
   { key = 't',          mods = mod.SUPER_REV, action = act.SpawnTab({ DomainName = 'wsl:ubuntu-fish' }) },
   { key = 'w',          mods = mod.SUPER_REV, action = act.CloseCurrentTab({ confirm = false }) },

   -- tabs: navigation
   { key = '[',          mods = mod.SUPER,     action = act.ActivateTabRelative(-1) },
   { key = ']',          mods = mod.SUPER,     action = act.ActivateTabRelative(1) },
   { key = '[',          mods = mod.SUPER_REV, action = act.MoveTabRelative(-1) },
   { key = ']',          mods = mod.SUPER_REV, action = act.MoveTabRelative(1) },

   -- tab: title
   { key = '0',          mods = mod.SUPER,     action = act.EmitEvent('tabs.manual-update-tab-title') },
   { key = '0',          mods = mod.SUPER_REV, action = act.EmitEvent('tabs.reset-tab-title') },

   -- tab: hide tab-bar
   { key = '9',          mods = mod.SUPER,     action = act.EmitEvent('tabs.toggle-tab-bar'), },

   -- window --
   -- window: spawn windows
   { key = 'n',          mods = mod.SUPER,     action = act.SpawnWindow },

   -- window: zoom window
   {
      key = '-',
      mods = mod.SUPER,
      action = wezterm.action_callback(function(window, _pane)
         local dimensions = window:get_dimensions()
         -- on Windows 11 (the only OS I'm able to test this on), `is_full_screen` is always false (it's a bug).
         -- Calling `set_inner_size` when the window is actually in fullscreen will cause the
         -- program UI to completely freeze.
         if platform.is_win or dimensions.is_full_screen then
            return
         end
         local new_width = dimensions.pixel_width - 50
         local new_height = dimensions.pixel_height - 50
         window:set_inner_size(new_width, new_height)
      end)
   },
   {
      key = '=',
      mods = mod.SUPER,
      action = wezterm.action_callback(function(window, _pane)
         local dimensions = window:get_dimensions()
         -- on Windows 11 (the only OS I'm able to test this on), `is_full_screen` is always false (it's a bug).
         -- Calling `set_inner_size` when the window is actually in fullscreen will cause the
         -- program UI to completely freeze.
         if platform.is_win or dimensions.is_full_screen then
            return
         end
         local new_width = dimensions.pixel_width + 50
         local new_height = dimensions.pixel_height + 50
         window:set_inner_size(new_width, new_height)
      end)
   },
   {
      key = 'Enter',
      mods = mod.SUPER_REV,
      action = wezterm.action_callback(function(window, _pane)
         window:maximize()
      end)
   },

   -- background controls --
   {
      key = [[/]],
      mods = mod.SUPER,
      action = wezterm.action_callback(function(window, _pane)
         backdrops:random(window)
      end),
   },
   {
      key = [[,]],
      mods = mod.SUPER,
      action = wezterm.action_callback(function(window, _pane)
         backdrops:cycle_back(window)
      end),
   },
   {
      key = [[.]],
      mods = mod.SUPER,
      action = wezterm.action_callback(function(window, _pane)
         backdrops:cycle_forward(window)
      end),
   },
   {
      key = [[/]],
      mods = mod.SUPER_REV,
      action = act.InputSelector({
         title = 'InputSelector: Select Background',
         choices = backdrops:choices(),
         fuzzy = true,
         fuzzy_description = 'Select Background: ',
         action = wezterm.action_callback(function(window, _pane, idx)
            if not idx then
               return
            end
            ---@diagnostic disable-next-line: param-type-mismatch
            backdrops:set_img(window, tonumber(idx))
         end),
      }),
   },
   {
      key = 'b',
      mods = mod.SUPER,
      action = wezterm.action_callback(function(window, _pane)
         backdrops:toggle_focus(window)
      end)
   },

   -- panes --
   -- panes: split panes
   {
      key = [[\]],
      mods = mod.SUPER,
      action = act.SplitHorizontal({ domain = 'CurrentPaneDomain' }),
   },
   {
      key = [[-]],
      mods = mod.SUPER,
      action = act.SplitVertical({ domain = 'CurrentPaneDomain' }),
   },

   -- panes: zoom+close pane
   { key = 'Enter', mods = mod.SUPER,     action = act.TogglePaneZoomState },
   { key = 'w',     mods = mod.SUPER,     action = act.CloseCurrentPane({ confirm = false }) },

   -- panes: navigation
   { key = 'k',     mods = mod.SUPER_REV, action = act.ActivatePaneDirection('Up') },
   { key = 'j',     mods = mod.SUPER_REV, action = act.ActivatePaneDirection('Down') },
   { key = 'h',     mods = mod.SUPER_REV, action = act.ActivatePaneDirection('Left') },
   { key = 'l',     mods = mod.SUPER_REV, action = act.ActivatePaneDirection('Right') },
   {
      key = 'p',
      mods = mod.SUPER_REV,
      action = act.PaneSelect({ alphabet = '1234567890', mode = 'SwapWithActiveKeepFocus' }),
   },

   -- panes: scroll pane
   { key = 'u',        mods = mod.SUPER, action = act.ScrollByLine(-5) },
   { key = 'd',        mods = mod.SUPER, action = act.ScrollByLine(5) },
   { key = 'PageUp',   mods = 'NONE',    action = act.ScrollByPage(-0.75) },
   { key = 'PageDown', mods = 'NONE',    action = act.ScrollByPage(0.75) },

   -- key-tables --
   -- resizes fonts
   {
      key = 'f',
      mods = 'LEADER',
      action = act.ActivateKeyTable({
         name = 'resize_font',
         one_shot = false,
         timeout_milliseconds = 1000,
      }),
   },
   -- resize panes
   {
      key = 'p',
      mods = 'LEADER',
      action = act.ActivateKeyTable({
         name = 'resize_pane',
         one_shot = false,
         timeout_milliseconds = 1000,
      }),
   },
}

if platform.is_mac then
   -- Match macOS text editing: Ctrl+Delete is character delete, Option+Delete
   -- is word delete, and Command+Delete is line delete.
   table.insert(keys, { key = 'Backspace', mods = 'CTRL', action = act.SendString('\u{7f}') })
   table.insert(keys, { key = 'Backspace', mods = 'ALT', action = act.SendString('\u{17}') })
   table.insert(keys, { key = 'Backspace', mods = mod.SUPER, action = act.SendString('\u{15}') })
   table.insert(keys, { key = 'Enter', mods = 'SUPER|SHIFT', action = act.SendString('\u{1b}\r') })
   table.insert(keys, { key = 'a', mods = mod.SUPER, action = act.SendString('\u{1b}a') })
elseif platform.is_linux or platform.is_win then
   -- Match Linux/Windows text editing for Ctrl+Delete, while adding Alt+Delete
   -- as a terminal-local line delete pair to match Alt+Left/Right line movement.
   table.insert(keys, { key = 'Backspace', mods = 'CTRL', action = act.SendString('\u{17}') })
   table.insert(keys, { key = 'phys:Delete', mods = 'CTRL', action = act.SendString('\u{1b}[3;5~') })
   table.insert(keys, { key = 'Backspace', mods = 'ALT', action = act.SendString('\u{15}') })
   table.insert(keys, { key = 'phys:Delete', mods = 'ALT', action = act.SendString('\u{1b}[3;3~') })
   table.insert(keys, { key = 'Backspace', mods = 'SUPER', action = act.Nop })
   table.insert(keys, { key = 'phys:Delete', mods = 'SUPER', action = act.Nop })
end

-- stylua: ignore
---@type table<string, Key[]>
local key_tables = {
   resize_font = {
      { key = 'k',      action = act.IncreaseFontSize },
      { key = 'j',      action = act.DecreaseFontSize },
      { key = 'r',      action = act.ResetFontSize },
      { key = 'Escape', action = 'PopKeyTable' },
      { key = 'q',      action = 'PopKeyTable' },
   },
   resize_pane = {
      { key = 'k',      action = act.AdjustPaneSize({ 'Up', 1 }) },
      { key = 'j',      action = act.AdjustPaneSize({ 'Down', 1 }) },
      { key = 'h',      action = act.AdjustPaneSize({ 'Left', 1 }) },
      { key = 'l',      action = act.AdjustPaneSize({ 'Right', 1 }) },
      { key = 'Escape', action = 'PopKeyTable' },
      { key = 'q',      action = 'PopKeyTable' },
   },
}

---@type MouseBinding[]
local mouse_bindings = {
   -- Ctrl-click will open the link under the mouse cursor
   {
      event = { Up = { streak = 1, button = 'Left' } },
      mods = 'CTRL',
      action = act.OpenLinkAtMouseCursor,
   },
   {
      event = { Up = { streak = 1, button = 'Right' } },
      mods = 'NONE',
      action = act({ PasteFrom = "Clipboard" }),
   },
}

---@type Config
return {
   disable_default_key_bindings = true,
   -- disable_default_mouse_bindings = true,
   leader = { key = 'Space', mods = mod.LEADER },
   keys = keys,
   key_tables = key_tables,
   mouse_bindings = mouse_bindings,
}
