# WezTerm config

My [WezTerm](https://github.com/wez/wezterm) config for Arch Linux and macOS. It is a fork of
[KevinSilvester/wezterm-config](https://github.com/KevinSilvester/wezterm-config) and keeps its
MIT license (see [LICENSE](./LICENSE)). The `is_win` branches come from upstream and are
untested here.

## Install

This repo is a submodule of my [dotfiles](https://github.com/Junf137/dotfiles), whose
`bootstrap.sh` creates two links:

- this repo to `~/.config/wezterm`;
- `~/Pictures/Background` to `~/.config/wezterm/backdrops/` (gitignored). A random image from
  it is the background at startup; when it is missing or empty, `default_bg.jpeg` is used.

The font is FiraCode Nerd Font Mono (Homebrew cask `font-fira-code-nerd-font`).

## What it does

- The startup window opens maximized as a regular window, not in macOS fullscreen. It has no
  title bar, but the resize borders work on every platform.
- Tab titles show the process (shells and tmux as icons), unseen output and OSC 9;4 progress
  (progress needs wezterm 20250209 or newer). The left status shows the active key table or
  leader, the right status the date and battery.
- The bell plays a system sound: `paplay` on Linux, `afplay` on macOS.
- `utils/gpu-adapter.lua` picks the best GPU and graphics API for the `WebGpu` front end.

## Check

`tests/window-defaults.lua` loads the whole config without opening a window and asserts the
startup, resize-border and leader defaults:

```sh
wezterm --config-file tests/window-defaults.lua show-keys | head -1
```

It prints `Leader: Physical(Space) ALT | CTRL 1s` only when every assertion passed. A failed
assertion still exits 0: wezterm falls back to its built-in config, which has no leader. CI
runs stylua and luacheck on pushes and pull requests to `main` (`.github/workflows/lint.yml`).

## Key bindings

`wezterm show-keys` prints the authoritative list for the platform it runs on.

- `SUPER` is Cmd on macOS and Alt on Linux; `SUPER_REV` is Cmd+Ctrl or Alt+Ctrl.
- `LEADER` is Ctrl+Alt+Space everywhere. Upstream's `SUPER_REV+Space` is taken on macOS by the
  Emoji & Symbols menu.
- `Backspace` is the key macOS labels delete.

| Keys                                        | Action                                                          |
| ------------------------------------------- | --------------------------------------------------------------- |
| `F1` / `F2`                                 | Copy mode / command palette                                     |
| `F3` / `F4` / `F5`                          | Launcher / fuzzy tab list / fuzzy workspace list                |
| `F6`                                        | Open a tab per local tmux session; pressing again replaces them |
| `F7`                                        | Pick a local tmux session and attach it in a new tab            |
| `F8`                                        | Same, for the tmux sessions on `REMOTE_HOST` over ssh           |
| `F11` / `F12`                               | Toggle fullscreen / debug overlay                               |
| `SUPER+f`                                   | Search the scrollback                                           |
| `SUPER_REV+u`                               | Quick-select a URL and open it                                  |
| `Ctrl+Shift+c` / `Ctrl+Shift+v`             | Copy / paste                                                    |
| `SUPER+Left` / `SUPER+Right`                | Move the cursor to the line start / end                         |
| `SUPER+t` / `SUPER_REV+w`                   | New tab / close the tab                                         |
| `SUPER+[` / `SUPER+]`                       | Previous / next tab                                             |
| `SUPER_REV+[` / `SUPER_REV+]`               | Move the tab left / right                                       |
| `SUPER+0` / `SUPER_REV+0`                   | Rename the tab / undo the rename                                |
| `SUPER+9`                                   | Toggle the tab bar                                              |
| `SUPER+n`                                   | New window                                                      |
| `SUPER+=`                                   | Grow the window by 50 px (not in fullscreen)                    |
| `SUPER_REV+Enter`                           | Maximize the window                                             |
| `SUPER+\` / `SUPER+-`                       | Split side by side / stacked, as in tmux                        |
| `SUPER+Enter` / `SUPER+w`                   | Zoom / close the pane                                           |
| `SUPER_REV+h` `j` `k` `l`                   | Focus the pane left / down / up / right                         |
| `SUPER_REV+p`                               | Swap the pane with a picked one                                 |
| `SUPER+u` / `SUPER+d`                       | Scroll 5 lines up / down                                        |
| `PageUp` / `PageDown`                       | Scroll 3/4 of a page up / down                                  |
| `SUPER+/`                                   | Random background                                               |
| `SUPER+,` / `SUPER+.`                       | Previous / next background                                      |
| `SUPER_REV+/`                               | Fuzzy-select a background                                       |
| `SUPER+b`                                   | Toggle the background image                                     |
| `LEADER` then `f`                           | Font size: `k` bigger, `j` smaller, `r` reset, `q`/`Esc` leave  |
| `LEADER` then `p`                           | Pane size: `h` `j` `k` `l` resize, `q`/`Esc` leave              |
| `Ctrl+click`                                | Open the link under the mouse                                   |
| Right-click                                 | Paste; on the `+` tab button, open the launch menu              |
| `Cmd+a` (macOS)                             | Send `M-a`, the tmux prefix                                     |
| `Cmd+Shift+Enter` (macOS)                   | Send `ESC CR`, the Alt+Enter sequence                           |
| `Ctrl`/`Option`/`Cmd+Backspace` (macOS)     | Delete a character / the previous word / to the line start      |
| `Ctrl+Backspace` / `Ctrl+Delete` (Linux)    | Delete the previous / next word                                 |
| `Alt+Backspace` / `Alt+Delete` (Linux)      | Delete to the line start / end                                  |
| `Super+Backspace` / `Super+Delete` (Linux)  | Nothing                                                         |

## References

- <https://github.com/rxi/lume>
- <https://github.com/catppuccin/wezterm>
- <https://github.com/wez/wezterm/discussions/628#discussioncomment-1874614>
- <https://github.com/wez/wezterm/discussions/628#discussioncomment-5942139>
