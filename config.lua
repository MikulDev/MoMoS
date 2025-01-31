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

config.screenshot_path = "$HOME/Screenshots/"

-- Splits the display into 2 logical "screens" with their own taskbars & tags
-- Only for monitors wider than 16:9
-- Some applications (like recording software) don't acknowledge the split
config.split_ultrawide = true

config.wallpaper_interval = 600

-- }}}

return config