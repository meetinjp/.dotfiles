local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- Launch WSL Arch Linux instead of cmd/PowerShell. The domain name is
-- "WSL:" + the distribution name reported by `wsl -l -v` (here: archlinux).
-- The default user comes from /etc/wsl.conf inside the distro.
config.default_domain = 'WSL:archlinux'

config.font = wezterm.font 'FiraCode Nerd Font Mono'
config.font_size = 16.0

config.color_scheme = 'GruvboxDarkHard'

config.hide_tab_bar_if_only_one_tab = true
config.window_padding = { left = 6, right = 6, top = 4, bottom = 4 }

return config
