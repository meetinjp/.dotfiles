local wezterm = require 'wezterm'
local act = wezterm.action
local config = wezterm.config_builder()

-- Hybrid-graphics laptops: when Windows swaps GPUs the cached WebGpu adapter
-- goes stale and WezTerm aborts with "Load library failed with error 126";
-- OpenGL meanwhile fails with "OpenGL implementation is too old to work with
-- glium" on this iGPU. Stay on WebGpu but pin to the iGPU via LowPower so the
-- adapter never swaps under us.
config.front_end = 'WebGpu'
config.webgpu_power_preference = 'LowPower'

-- Keep the pane open if its pty dies (WSL OOM-kill, ssh drop, crash). Without
-- this, the last tab's pty death silently closes the whole window so the
-- failure is invisible.
config.exit_behavior = 'Hold'

-- Launch WSL Arch Linux instead of cmd/PowerShell. The domain name is
-- "WSL:" + the distribution name reported by `wsl -l -v` (here: archlinux).
-- The default user comes from /etc/wsl.conf inside the distro.
config.default_domain = 'WSL:archlinux'

-- Font + fallback chain (mirrors kitty: FiraCode Nerd Font Mono → Noto Mono
-- → Noto CJK JP → DejaVu).
config.font = wezterm.font_with_fallback {
  'FiraCode Nerd Font Mono',
  'Noto Sans Mono',
  'Noto Sans CJK JP',
  'DejaVu Sans Mono',
}
config.font_size = 16.0

-- Disable ligatures (kitty `disable_ligatures always` + `font_features none`).
config.harfbuzz_features = { 'calt=0', 'clig=0', 'liga=0' }

config.color_scheme = 'GruvboxDarkHard'

-- Solid block cursor, no blink, same when unfocused.
config.default_cursor_style = 'SteadyBlock'
config.cursor_blink_rate = 0

config.scrollback_lines = 10000
config.audible_bell = 'Disabled'

config.hide_tab_bar_if_only_one_tab = true
config.window_padding = { left = 6, right = 6, top = 4, bottom = 4 }

-- Keybindings ported from kitty. Anything not listed here keeps WezTerm's
-- defaults.
config.keys = {
  -- navigate tabs
  { key = 'h', mods = 'CTRL|SHIFT', action = act.ActivateTabRelative(-1) },
  { key = 'l', mods = 'CTRL|SHIFT', action = act.ActivateTabRelative(1) },

  -- move tabs
  { key = ',', mods = 'CTRL|SHIFT', action = act.MoveTabRelative(-1) },
  { key = '.', mods = 'CTRL|SHIFT', action = act.MoveTabRelative(1) },

  -- new tab in $HOME (kitty: ctrl+shift+t new_tab)
  {
    key = 't',
    mods = 'CTRL|SHIFT',
    action = act.SpawnCommandInNewTab {
      domain = { DomainName = 'WSL:archlinux' },
      cwd = '/home/kacper',
    },
  },

  -- new tab in current cwd (kitty: ctrl+shift+y new_tab_with_cwd)
  -- Relies on the shell emitting OSC 7 so wezterm knows the cwd.
  { key = 'y', mods = 'CTRL|SHIFT', action = act.SpawnTab 'CurrentPaneDomain' },

  -- close tab without confirm (kitty: ctrl+shift+q close_tab)
  { key = 'q', mods = 'CTRL|SHIFT', action = act.CloseCurrentTab { confirm = false } },

  -- tab picker (kitty: ctrl+shift+j select_tab)
  { key = 'j', mods = 'CTRL|SHIFT', action = act.ShowTabNavigator },

  -- rename tab (kitty: ctrl+shift+alt+t set_tab_title)
  {
    key = 't',
    mods = 'CTRL|SHIFT|ALT',
    action = act.PromptInputLine {
      description = 'Enter new tab title',
      action = wezterm.action_callback(function(window, _, line)
        if line then window:active_tab():set_title(line) end
      end),
    },
  },
}

-- Ctrl+1..Ctrl+9 jump straight to tab N (1-indexed).
for i = 1, 9 do
  table.insert(config.keys, {
    key = tostring(i),
    mods = 'CTRL',
    action = act.ActivateTab(i - 1),
  })
end

return config
