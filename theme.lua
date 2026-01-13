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

-- Colors
theme.light_gray  =   "#9F9F9F"
theme.gray        =   "#595959"
theme.dark_gray   =   "#252525"
theme.black       =   "#161616"
theme.pitch_black =   "#131313"
theme.white       =   "#ffffff"
theme.selected    =   "#83B3F9"
theme.selected_dark =   "#424D64"
theme.selected_extradark =  "#282F3A"

local tag_shape = function(cr, width, height)
    gears.shape.rounded_rect(cr, width, height, dpi(4))
end

function font_with_size(size)
	return (theme.font or "Sans") .. " " .. size
end

-- Fonts
theme.font = "Gadugi Normal"

theme.taglist_font_size = 12
theme.tasklist_font_size = 10
theme.notification_font_size = 12
theme.update_entry_font_size = 12
theme.textclock_date_font_size = 9
theme.textclock_time_font_size = 11

theme.taglist_font  = font_with_size(theme.taglist_font_size)
theme.tasklist_font = font_with_size(theme.tasklist_font_size)
theme.notification_font = font_with_size(theme.notification_font_size)
theme.textclock_date_font = font_with_size(theme.textclock_date_font_size)
theme.textclock_time_font = font_with_size(theme.textclock_time_font_size)

-- General
theme.bg_normal     = theme.pitch_black .. "da"
theme.bg_systray    = theme.black
theme.systray_icon_spacing = dpi(8)
theme.bg_focus      = "#535d6c"
theme.bg_urgent     = "#ff0000"
theme.bg_minimize   = "#444444"
theme.wibar_height = dpi(52)

theme.fg_normal     = theme.light_gray .. "d0"
theme.fg_focus      = theme.white
theme.fg_urgent     = theme.white
theme.fg_minimize   = theme.light_gray .. "b0"

theme.textbox_fg = theme.white .. "aa"
theme.textbox_fg_selection  = theme.selected .. "88"
theme.textbox_fg_selected   = theme.pitch_black

theme.snap_border_width = 0
theme.useless_gap   = dpi(0)
theme.border_width  = dpi(1)
theme.border_normal = theme.pitch_black
theme.border_focus  = theme.gray
theme.border_marked = "#91231c"

-- Tags
theme.taglist_bg_focus = theme.light_gray .. "60"
theme.taglist_fg_focus = theme.white
theme.taglist_bg_urgent = theme.black .. "00"
theme.taglist_urgent = "#7591DA"
theme.taglist_dot = theme.white
theme.taglist_spacing = dpi(6)
theme.taglist_shape = tag_shape
theme.taglist_shape_border_width = 1
theme.taglist_shape_border_color = theme.white .. "20"
theme.taglist_shape_border_color_focus = theme.white .. "40"
theme.taglist_collapse_color = theme.white .. "99"
theme.taglist_collapse_color_hover = theme.white .. "ff"

-- Tasks
theme.tasklist_shape = tag_shape
theme.tasklist_spacing = dpi(10)
theme.tasklist_bg_focus = theme.light_gray .. "60"
theme.tasklist_fg_focus = theme.white
theme.tasklist_fg_normal = theme.white .. "90"
theme.tasklist_bg_normal = theme.gray .. "40"
theme.tasklist_bg_urgent = theme.selected .. "80"
theme.tasklist_fg_minimize = theme.light_gray .. "b0"
theme.tasklist_bg_minimize = theme.pitch_black .. "a0"
theme.tasklist_shape_border_color = theme.gray .. "a0"
theme.tasklist_shape_border_color_focus = theme.white .. "40"
theme.tasklist_shape_border_color_minimized = theme.gray .. "90"
theme.tasklist_shape_border_width = 1

-- Notifications
theme.notification_icon_size = dpi(60)
theme.notification_shape = tag_shape
theme.notification_bg = theme.black .. "b0"
theme.notification_border_color = theme.gray
theme.notification_fg = theme.white .. "b0"
theme.notification_margin = dpi(16)
naughty.config.defaults.margin = theme.notification_margin

-- App Menu
theme.appmenu = {}
theme.appmenu.bg = theme.pitch_black .. "dd"
theme.appmenu.button_bg = theme.dark_gray .. "dd"
theme.appmenu.button_bg_focus = theme.gray .. "88"
theme.appmenu.button_bg_sudo = "#666455" .. "77"
theme.appmenu.search_bg = theme.pitch_black .. "80"
theme.appmenu.pin_button_bg = theme.dark_gray .. "cc"
theme.appmenu.pin_button_bg_focus = theme.gray .. "88"
theme.appmenu.fg = theme.light_gray .. "d0"
theme.appmenu.border = theme.gray
theme.appmenu.button_border = theme.light_gray
theme.appmenu.button_border_focus = theme.white .. "55"
theme.appmenu.button_border_sudo = "#D9B775" .. "dd"

-- Shutdown
theme.shutdown = {}
theme.shutdown.bg = theme.pitch_black .. "88"
theme.shutdown.button_bg = theme.dark_gray .. "dd"
theme.shutdown.button_bg_focus = theme.gray .. "77"
theme.shutdown.fg = theme.light_gray .. "d0"
theme.shutdown.border = theme.gray .. "55"
theme.shutdown.border_focus = theme.white .. "55"

-- Calendar
theme.calendar = {}
theme.calendar.bg = theme.pitch_black .. "dd"
theme.calendar.date_bg = theme.dark_gray .. "66"
theme.calendar.date_bg_current = theme.selected .. "40"
theme.calendar.date_bg_hover = theme.selected .. "25"
theme.calendar.button_bg = theme.dark_gray .. "dd"
theme.calendar.button_bg_focus = theme.gray .. "aa"
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

-- Notification Menu
theme.notifications = {}
theme.notifications.bg = theme.pitch_black .. "dd"
theme.notifications.notif_bg = theme.pitch_black .. "00"
theme.notifications.notif_bg_hover = theme.dark_gray .. "dd"
theme.notifications.preview = theme.pitch_black .. "00"
theme.notifications.close_button_bg = theme.dark_gray
theme.notifications.close_button_bg_focus = theme.gray
theme.notifications.button_bg = theme.dark_gray .. "aa"
theme.notifications.button_bg_focus = theme.gray .. "aa"
theme.notifications.main_button_bg = theme.black .. "00"
theme.notifications.main_button_bg_focus = theme.gray .. "aa"
theme.notifications.button_fg = theme.white .. "aa"
theme.notifications.button_fg_focus = theme.white .. "ff"
theme.notifications.notif_border = theme.light_gray .. "33"
theme.notifications.notif_border_hover = theme.white .. "55"
theme.notifications.button_border = theme.light_gray .. "44"
theme.notifications.button_border_focus = theme.white .. "66"

-- Package Updates Menu
theme.updates = {}
theme.updates.bg = theme.pitch_black .. "bb"
theme.updates.fg = theme.white .. "aa"
theme.updates.entry_bg = theme.pitch_black .. "55"
theme.updates.entry_bg_hover = theme.dark_gray .. "dd"
theme.updates.preview = theme.pitch_black .. "00"
theme.updates.close_button_bg = theme.dark_gray
theme.updates.close_button_bg_focus = theme.gray
theme.updates.button_bg = theme.dark_gray .. "aa"
theme.updates.button_bg_focus = theme.gray .. "aa"
theme.updates.main_button_bg = theme.black .. "00"
theme.updates.main_button_bg_focus = theme.gray .. "aa"
theme.updates.button_fg = theme.white .. "aa"
theme.updates.button_fg_focus = theme.white .. "ff"
theme.updates.entry_border = theme.light_gray .. "33"
theme.updates.entry_border_hover = theme.white .. "55"
theme.updates.button_border = theme.light_gray .. "44"
theme.updates.button_border_focus = theme.white .. "66"

-- Taglist Launcher
theme.tglauncher = {}
theme.tglauncher.bg = theme.black .. "88"

-- Clock
theme.clock = {}
theme.clock.fg = theme.white .. "bb"
theme.clock.button_bg = theme.dark_gray .. "00"
theme.clock.button_bg_focus = theme.gray .. "55"
theme.clock.button_border = theme.light_gray .. "00"
theme.clock.button_border_focus = theme.white .. "44"

-- Music Widget
theme.music = {}
theme.music.bg = theme.dark_gray .. "00"
theme.music.fg = theme.white .. "ff"
theme.music.button_bg = theme.dark_gray .. "00"
theme.music.button_fg = theme.white
theme.music.border = theme.gray .. "00"
theme.music.progress_bg = theme.gray
theme.music.progress_fg = theme.white .. "bb"
theme.music.title_fg = theme.white .. "ff"
theme.music.artist_fg = theme.white .. "aa"
theme.music.time_fg = theme.white .. "aa"

-- Volume Widget
theme.volume = {}
theme.volume.bg = theme.pitch_black .. "dd"
theme.volume.fg = theme.white .. "aa"
theme.volume.fg_title = theme.white .. "dd"
theme.volume.fg_muted = theme.white .. "55"
theme.volume.border = "#3C3C3C" .. "dd"
theme.volume.separator = "#3C3C3C" .. "dd"
theme.volume.border_focus = "#89b4fa"
theme.volume.button_bg = theme.dark_gray .. "00"
theme.volume.button_bg_focus = theme.gray .. "55"
theme.volume.button_border = theme.light_gray .. "00"
theme.volume.button_border_focus = theme.white .. "44"
theme.volume.slider_bg = theme.light_gray .. "33"
theme.volume.slider_fg = theme.light_gray .. "88"
theme.volume.slider_border = theme.light_gray .. "88"
theme.volume.slider_handle = theme.dark_gray .. "ff"
theme.volume.slider_handle_border = theme.white .. "55"
theme.volume.app_bg = theme.dark_gray .. "66"
theme.volume.app_bg_hover = theme.gray .. "55"
theme.volume.app_border = theme.light_gray .. "55"

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
