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

-- The tmux the F6/F7 session launchers run. Always the local one, on whichever machine
-- this config is loaded on. It has to be an absolute path on macOS: wezterm is started
-- there by launchd from Finder/Dock with launchd's own minimal PATH
-- (/usr/bin:/bin:/usr/sbin:/sbin), Homebrew's bin is not on it, and both
-- run_child_process and spawn_tab exec directly rather than through a login shell that
-- would have fixed the PATH up. A bare 'tmux' fails with ENOENT there.
-- F8 never uses this: the tmux it drives is REMOTE_HOST's, and that name is resolved
-- over there, by the login shell ssh hands the command string to.
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

-- The machine F8 lists and attaches. A bare 'ssh' is safe where a bare 'tmux' was not:
-- /usr/bin/ssh is part of the base system on both platforms, and /usr/bin *is* on
-- launchd's minimal PATH. Checked from a stripped environment (`env -i`, so no
-- SSH_AUTH_SOCK either): key auth off ~/.ssh/id_ed25519 needs no agent behind it.
local SSH = 'ssh'
local REMOTE_HOST = 'bigyaboom2'

---list-sessions format shared by the local and the remote listing, so both parse the same
---way. Every field is printable and the free-form one is last, and neither is cosmetic. A
---tmux client whose locale does not name UTF-8 is not flagged UTF-8-capable, and the
---server then sanitises the output of commands it runs for that client, replacing every
---non-printable byte with '_'. Each client ssh starts is such a client: ssh forwards no
---LC_* by default, so the login shell it runs the command through has an empty locale. A
---tab separator survives the ssh channel intact and is then eaten on the far side --
---measured against tmux 3.7b, which is both ends here -- so the split has to be on
---something printable. Session names may hold spaces, hence the name last, behind two
---fields of fixed shape. A name holding non-printables is mangled the same way and would
---attach to the wrong thing, but tmux rejects most of what could do that in `-s`.
local SESSION_FMT = '#{session_windows} #{?session_attached,1,0} #{session_name}'

---Wrap `word` in single quotes for the remote shell that ssh runs its command string
---through. Everything inside is literal, which the format string above *needs*: `#`
---begins a word there, and an unquoted word-initial `#` is a comment, which would
---truncate the command rather than fail it.
local function shell_quote(word)
   local escaped = word:gsub("'", "'\\''")
   return "'" .. escaped .. "'"
end

---Run `argv`, returning its stdout, or nil plus a message fit to show the user.
---run_child_process has two failure modes and reports them differently: a process that
---ran and exited non-zero comes back as ok=false, but one that could not be spawned at
---all *raises*. Only pcall catches the second, and without it the raise tears the whole
---callback down before any toast or log runs -- so the single platform whose tmux path
---is a guess (macOS, where TMUX falls back to a bare 'tmux' that launchd's PATH cannot
---resolve) would fail with no diagnostic whatsoever. pcall shifts every return one place
---right, hence four names for three values.
local function run_argv(argv)
   local spawned, ok, stdout, stderr = pcall(wezterm.run_child_process, argv)
   if not spawned then
      -- In this branch `ok` is the raised error rather than a status, and it arrives as
      -- ~200 characters: the cause on the first line, then a Lua stack traceback naming
      -- poll/pcall/main chunk. Only the first line belongs in a desktop notification.
      local message = tostring(ok):match('^[^\n]*')
      return nil, 'cannot run ' .. argv[1] .. ': ' .. message
   end
   if not ok then
      -- tmux's own words: "no server running on ...", but equally "protocol version
      -- mismatch" after an upgrade, which naming one cause in the toast would misreport.
      -- Through ssh this is the *remote* tmux's stderr, or ssh's own when the hop failed.
      local message = tostring(stderr or ''):gsub('%s+$', '')
      return nil, message ~= '' and message or (argv[1] .. ' failed')
   end
   return stdout
end

---Split list-sessions output into { name, detail } pairs, rebuilding the detail SESSION_FMT
---deliberately does not spell out, so that every field it carries stays fixed in shape.
local function parse_sessions(stdout)
   local sessions = {}
   for line in stdout:gmatch('[^\n]+') do
      local windows, attached, name = line:match('^(%d+) ([01]) (.+)$')
      if name then
         table.insert(sessions, {
            name = name,
            detail = windows .. ' windows' .. (attached == '1' and ' (attached)' or ''),
         })
      end
   end
   return sessions
end

---The local tmux's sessions, or nil plus a message fit to show the user.
local function tmux_sessions()
   local stdout, err = run_argv({ TMUX, 'list-sessions', '-F', SESSION_FMT })
   if not stdout then
      return nil, err
   end
   return parse_sessions(stdout)
end

---REMOTE_HOST's tmux sessions, or nil plus a message that always names the host -- an
---unprefixed "no server running on ..." reads exactly like the local one.
---BatchMode is what stops a host that wants a password from hanging on a prompt nobody
---can answer: this child has no tty, and run_child_process blocks the gui thread until it
---returns. ConnectTimeout is the same guard against a host that is simply off, where
---ssh's default is the kernel's TCP timeout -- over a minute of frozen wezterm.
local function remote_sessions()
   local stdout, err = run_argv({
      SSH, '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5', REMOTE_HOST,
      'tmux list-sessions -F ' .. shell_quote(SESSION_FMT),
   })
   if not stdout then
      return nil, REMOTE_HOST .. ': ' .. err
   end
   return parse_sessions(stdout)
end

---argv that hard-attaches to `name` in whatever pane it is spawned into.
---`-A` attaches or creates, so a session that vanished between a listing and the attach
---can't fail. `-D` is what makes it a *hard* attach, detaching whatever client already
---holds the session -- the point rather than a side effect: two clients on one session
---clamp every window to the smaller client's size, so attaching from a second window
---without `-D` reshapes the session around the smaller one.
local function tmux_attach_argv(name)
   return { TMUX, 'new-session', '-A', '-D', '-s', name }
end

---The same hard attach, one ssh hop away. `-t` is not optional: ssh allocates a tty only
---when given no command to run, and tmux will not attach without one. No BatchMode here,
---unlike the listing -- this one lands in a real pane, where a prompt is answerable.
local function remote_attach_argv(name)
   return { SSH, '-t', REMOTE_HOST, 'tmux new-session -A -D -s ' .. shell_quote(name) }
end

---A fuzzy picker over `opts.list()`'s sessions that hard-attaches the chosen one, with
---`opts.attach`, in a new tab. The selector is raised with perform_action rather than
---returned: an action_callback's return value is discarded, so returning an action does
---nothing. `opts.label` names the machine in the title and the prompt and `opts.empty` is
---the toast for a server with no sessions, so a remote result never reads as a local one.
local function attach_picker(opts)
   return wezterm.action_callback(function(window, pane)
      local sessions, err = opts.list()
      if not sessions then
         wezterm.log_error(err)
         window:toast_notification('wezterm', err, nil, 4000)
         return
      end
      if #sessions == 0 then
         window:toast_notification('wezterm', opts.empty, nil, 4000)
         return
      end

      local choices = {}
      for _, session in ipairs(sessions) do
         -- `id` is what gets attached, `label` is what is shown and fuzzy-matched --
         -- so typing 'attached' narrows to the sessions that already hold a client.
         table.insert(choices, {
            id = session.name,
            label = session.name .. '  ' .. session.detail,
         })
      end

      window:perform_action(
         act.InputSelector({
            title = 'InputSelector: Attach ' .. opts.label .. ' Session',
            choices = choices,
            fuzzy = true,
            fuzzy_description = 'Attach ' .. opts.label .. ' session: ',
            action = wezterm.action_callback(function(inner_window, _inner_pane, id, _label)
               if not id then
                  return
               end
               inner_window:mux_window():spawn_tab({ args = opts.attach(id) })
            end),
         }),
         pane
      )
   end)
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
   -- Open one tab per local tmux session, enumerated at press-time. Tab labels come
   -- from the pane title, which `set-titles-string` in tmux.conf sets to `host · #S`.
   -- Pressing it a second time replaces that set rather than topping it up: the new
   -- clients hard-attach, `-D` detaches the ones the previous press left, and a client
   -- detached that way exits 0, so `exit_behavior = 'CloseOnCleanExit'` reaps its pane.
   -- The spawn happens before the detach, so the window is never momentarily tabless.
   {
      key = 'F6',
      mods = 'NONE',
      action = wezterm.action_callback(function(window, _pane)
         local sessions, err = tmux_sessions()
         if not sessions then
            wezterm.log_error(err)
            window:toast_notification('wezterm', err, nil, 4000)
            return
         end
         if #sessions == 0 then
            window:toast_notification('wezterm', 'no tmux sessions here', nil, 4000)
            return
         end

         local mux_win = window:mux_window()
         for _, session in ipairs(sessions) do
            mux_win:spawn_tab({ args = tmux_attach_argv(session.name) })
         end
      end),
   },
   -- Pick one local tmux session from a fuzzy list and hard-attach it in a new tab.
   {
      key = 'F7',
      mods = 'NONE',
      action = attach_picker({
         label = 'tmux',
         empty = 'no tmux sessions here',
         list = tmux_sessions,
         attach = tmux_attach_argv,
      }),
   },
   -- The same picker one ssh hop away, over REMOTE_HOST's sessions. Everything that makes
   -- the local attach work survives the hop: the remote tmux writes its title through the
   -- ssh pty like any other, so the tab is labelled by `set-titles-string` there too --
   -- whose 5-char host field is the only thing telling a remote tab from a local one --
   -- and a second press re-attaches with `-D`, whose displaced ssh exits 0, so
   -- `exit_behavior = 'CloseOnCleanExit'` reaps the pane it left behind.
   {
      key = 'F8',
      mods = 'NONE',
      action = attach_picker({
         label = REMOTE_HOST,
         empty = 'no tmux sessions on ' .. REMOTE_HOST,
         list = remote_sessions,
         attach = remote_attach_argv,
      }),
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
