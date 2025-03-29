local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local naughty = require("naughty")
local wibox = require("wibox")
local dpi = require("beautiful.xresources").apply_dpi

config = {}

-- {{{ Default Applications

config.compositor = "picom"
config.terminal = "alacritty"
config.editor = os.getenv("EDITOR") or "gedit"
config.web_browser = "firefox"
config.bluetooth = config.terminal .. " -e bluetuith"

-- }}}


-- {{{ Settings

-- Popular modkeys are: "Control", "Mod1" (Alt), "Mod4" (OS Key)
config.modkey = "Mod4"

config.notifications = {
    timeout = 10,  -- Time in seconds before hiding notifications
    max_width = dpi(400),  -- Maximum width of the notification list
    max_height = dpi(400), -- Maximum height of the notification list
    icon_size = dpi(32),   -- Size of icons in the notification list entries
    button_size = dpi(16), -- Size of the notification button in wibar
    entry_height = dpi(60), -- Height of each notification entry
    dont_store = {
        "spotify",
        ""
    }
}

config.music_players = {
    "spotify",
    "mpv",
    "vlc",
    "firefox",
    "chromium"
}
config.music_widget_timeout = 60

-- }}}

--{{{ Screen

-- Splits the display into 2 logical "screens" with their own taskbars & tags
-- Only for monitors wider than 16:9
-- Some applications (like recording software) don't acknowledge the split
config.split_ultrawide = true

config.screenshot_path = "$HOME/Screenshots/"
config.wallpaper_interval = 600
--}}}

return config