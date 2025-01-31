---------------------------
-- Default awesome theme --
---------------------------

local gears = require("gears")
local theme_assets = require("beautiful.theme_assets")
local xresources = require("beautiful.xresources")
local dpi = xresources.apply_dpi

local gfs = require("gears.filesystem")
local themes_path = gfs.get_themes_dir()
local naughty = require("naughty")

local theme = {}

light_gray  =   "#9F9F9F"
gray        =   "#595959"
dark_gray   =   "#252525"
black       =   "#161616"
pitch_black =   "#131313"
white       =   "#ffffff"
selected    =   "#83B3F9"
selected_dark   =   "#424D64"
theme.light_gray = light_gray
theme.gray = gray
theme.dark_gray = dark_gray
theme.black = black
theme.pitch_black = pitch_black
theme.white = white
theme.selected = selected
theme.selected_dark = selected_dark

local tag_shape = function(cr, width, height)
    gears.shape.rounded_rect(cr, width, height, 4)
end

function font_with_size(size)
	return theme.font .. " " .. size
end

theme.font = "Gadugi Normal"
theme.taglist_font  = font_with_size(dpi(13))
theme.tasklist_font = font_with_size(dpi(11))

theme.bg_normal     = pitch_black .. "da"
theme.bg_systray    = black
theme.systray_icon_spacing = dpi(8)
theme.bg_focus      = "#535d6c"
theme.bg_urgent     = "#ff0000"
theme.bg_minimize   = "#444444"
theme.wibar_height = dpi(52)

theme.fg_normal     = light_gray .. "d0"
theme.fg_focus      = white
theme.fg_urgent     = white
theme.fg_minimize   = light_gray .. "b0"

theme.snap_border_width = 0
theme.useless_gap   = dpi(0)
theme.border_width  = dpi(1)
theme.border_normal = pitch_black
theme.border_focus  = gray
theme.border_marked = "#91231c"

-- Tags
theme.taglist_bg_focus = light_gray .. "60"
theme.taglist_fg_focus = white
theme.taglist_bg_urgent = black .. "00"
theme.taglist_urgent = "#7591DA"
theme.taglist_dot = white
theme.taglist_spacing = dpi(6)
theme.taglist_shape = tag_shape
theme.taglist_shape_border_width = 1
theme.taglist_shape_border_color = white .. "20"
theme.taglist_shape_border_color_focus = white .. "40"

-- Tasks
theme.tasklist_shape = tag_shape
theme.tasklist_spacing = dpi(10)
theme.tasklist_bg_focus = light_gray .. "60"
theme.tasklist_fg_focus = white
theme.tasklist_fg_normal = white .. "90"
theme.tasklist_bg_normal = gray .. "40"
theme.tasklist_bg_urgent = selected .. "80"
theme.tasklist_fg_minimize = light_gray .. "b0"
theme.tasklist_bg_minimize = pitch_black .. "a0"
theme.tasklist_shape_border_color = gray .. "a0"
theme.tasklist_shape_border_color_focus = white .. "40"
theme.tasklist_shape_border_color_minimized = gray .. "90"
theme.tasklist_shape_border_width = 1

-- Notifications
theme.notification_icon_size = dpi(60)
theme.notification_font = font_with_size(dpi(12))
theme.notification_shape = tag_shape
theme.notification_bg = black .. "b0"
theme.notification_border_color = gray
theme.notification_fg = white .. "b0"
theme.notification_margin = dpi(16)
naughty.config.defaults.margin = theme.notification_margin

-- App Menu
theme.appmenu = {}
theme.appmenu.bg = theme.pitch_black .. "dd"
theme.appmenu.button_bg = theme.dark_gray .. "dd"
theme.appmenu.button_bg_focus = theme.selected_dark .. "77"
theme.appmenu.search_bg = theme.pitch_black .. "80"
theme.appmenu.pin_button_bg = theme.dark_gray .. "cc"
theme.appmenu.fg = theme.light_gray .. "d0"
theme.appmenu.border = theme.gray
theme.appmenu.button_border = theme.light_gray
theme.appmenu.button_border_focus = theme.white

-- Calendar
theme.calendar = {}
theme.calendar.bg = theme.pitch_black .. "dd"
theme.calendar.date_bg = theme.dark_gray .. "66"
theme.calendar.date_bg_current = theme.selected .. "40"
theme.calendar.date_bg_hover = theme.selected .. "25"
theme.calendar.button_bg = theme.dark_gray .. "dd"
theme.calendar.button_bg_focus = theme.selected_dark .. "77"
theme.calendar.month_fg = theme.white
theme.calendar.day_fg = theme.white .. "aa"
theme.calendar.date_fg = theme.light_gray .. "ff"
theme.calendar.date_fg_hover = theme.white
theme.calendar.date_fg_current = theme.white
theme.calendar.border = "#3C3C3C" .. "00"
theme.calendar.date_border = theme.light_gray
theme.calendar.date_border_hover = theme.white
theme.calendar.date_border_current = theme.white
theme.calendar.button_border = theme.light_gray .. "66"
theme.calendar.button_border_focus = theme.white .. "88"

-- Clock
theme.clock = {}
theme.clock.fg = theme.white .. "aa"

-- There are other variable sets
-- overriding the default one when
-- defined, the sets are:
-- taglist_[bg|fg]_[focus|urgent|occupied|empty|volatile]
-- tasklist_[bg|fg]_[focus|urgent]
-- titlebar_[bg|fg]_[normal|focus]
-- tooltip_[font|opacity|fg_color|bg_color|border_width|border_color]
-- mouse_finder_[color|timeout|animate_timeout|radius|factor]
-- prompt_[fg|bg|fg_cursor|bg_cursor|font]
-- hotkeys_[bg|fg|border_width|border_color|shape|opacity|modifiers_fg|label_bg|label_fg|group_margin|font|description_font]
-- Example:
--theme.taglist_bg_focus = "#ff0000"

-- Generate taglist squares:
local taglist_square_size = dpi(6)
--theme.taglist_squares_sel = gears.filesystem.get_configuration_dir()  .. "theme-icons/taglist_dot_focus.png"
--theme.taglist_squares_unsel = gears.filesystem.get_configuration_dir()  .. "theme-icons/taglist_dot_unfocus.png"

-- Variables set for theming notifications:
-- notification_font
-- notification_[bg|fg]
-- notification_[width|height|margin]
-- notification_[border_color|border_width|shape|opacity]

-- Variables set for theming the menu:
-- menu_[bg|fg]_[normal|focus]
-- menu_[border_color|border_width]
theme.menu_submenu_icon = themes_path.."default/submenu.png"
theme.menu_height = dpi(20)
theme.menu_width  = dpi(160)

-- You can add as many variables as
-- you wish and access them by using
-- beautiful.variable in your rc.lua
--theme.bg_widget = "#cc0000"

-- Define the image to load
theme.titlebar_close_button_normal = themes_path.."default/titlebar/close_normal.png"
theme.titlebar_close_button_focus  = themes_path.."default/titlebar/close_focus.png"

theme.titlebar_minimize_button_normal = themes_path.."default/titlebar/minimize_normal.png"
theme.titlebar_minimize_button_focus  = themes_path.."default/titlebar/minimize_focus.png"

theme.titlebar_ontop_button_normal_inactive = themes_path.."default/titlebar/ontop_normal_inactive.png"
theme.titlebar_ontop_button_focus_inactive  = themes_path.."default/titlebar/ontop_focus_inactive.png"
theme.titlebar_ontop_button_normal_active = themes_path.."default/titlebar/ontop_normal_active.png"
theme.titlebar_ontop_button_focus_active  = themes_path.."default/titlebar/ontop_focus_active.png"

theme.titlebar_sticky_button_normal_inactive = themes_path.."default/titlebar/sticky_normal_inactive.png"
theme.titlebar_sticky_button_focus_inactive  = themes_path.."default/titlebar/sticky_focus_inactive.png"
theme.titlebar_sticky_button_normal_active = themes_path.."default/titlebar/sticky_normal_active.png"
theme.titlebar_sticky_button_focus_active  = themes_path.."default/titlebar/sticky_focus_active.png"

theme.titlebar_floating_button_normal_inactive = themes_path.."default/titlebar/floating_normal_inactive.png"
theme.titlebar_floating_button_focus_inactive  = themes_path.."default/titlebar/floating_focus_inactive.png"
theme.titlebar_floating_button_normal_active = themes_path.."default/titlebar/floating_normal_active.png"
theme.titlebar_floating_button_focus_active  = themes_path.."default/titlebar/floating_focus_active.png"

theme.titlebar_maximized_button_normal_inactive = themes_path.."default/titlebar/maximized_normal_inactive.png"
theme.titlebar_maximized_button_focus_inactive  = themes_path.."default/titlebar/maximized_focus_inactive.png"
theme.titlebar_maximized_button_normal_active = themes_path.."default/titlebar/maximized_normal_active.png"
theme.titlebar_maximized_button_focus_active  = themes_path.."default/titlebar/maximized_focus_active.png"

theme.wallpaper = themes_path.."default/background.png"

-- You can use your own layout icons like this:
theme.layout_fairh = themes_path.."default/layouts/fairhw.png"
theme.layout_fairv = themes_path.."default/layouts/fairvw.png"
theme.layout_floating  = themes_path.."default/layouts/floatingw.png"
theme.layout_magnifier = themes_path.."default/layouts/magnifierw.png"
theme.layout_max = themes_path.."default/layouts/maxw.png"
theme.layout_fullscreen = themes_path.."default/layouts/fullscreenw.png"
theme.layout_tilebottom = themes_path.."default/layouts/tilebottomw.png"
theme.layout_tileleft   = themes_path.."default/layouts/tileleftw.png"
theme.layout_tile = themes_path.."default/layouts/tilew.png"
theme.layout_tiletop = themes_path.."default/layouts/tiletopw.png"
theme.layout_spiral  = themes_path.."default/layouts/spiralw.png"
theme.layout_dwindle = themes_path.."default/layouts/dwindlew.png"
theme.layout_cornernw = themes_path.."default/layouts/cornernww.png"
theme.layout_cornerne = themes_path.."default/layouts/cornernew.png"
theme.layout_cornersw = themes_path.."default/layouts/cornersww.png"
theme.layout_cornerse = themes_path.."default/layouts/cornersew.png"

-- Generate Awesome icon:
theme.awesome_icon = theme_assets.awesome_icon(
    theme.menu_height, theme.bg_focus, theme.fg_focus
)

-- Define the icon theme for application icons. If not set then the icons
-- from /usr/share/icons and /usr/share/icons/hicolor will be used.
theme.icon_theme = nil

return theme

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
