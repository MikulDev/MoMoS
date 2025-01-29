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

-- }}}

return config