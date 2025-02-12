-- If LuaRocks is installed, make sure that packages installed through it are
-- found (e.g. lgi). If LuaRocks is not installed, do nothing.
pcall(require, "luarocks.loader")

-- Standard awesome library
local gears = require("gears")
local awful = require("awful")
local cairo = require("lgi").cairo
local xresources = require("beautiful.xresources")
local dpi = xresources.apply_dpi
local math = require("math")
require("awful.autofocus")

local config_dir = gears.filesystem.get_configuration_dir()

local util = require("util")

-- Theme
local theme = load_util("theme")

-- Widget and layout library
local wibox = require("wibox")

-- Theme handling library
local beautiful = require("beautiful")

-- Notification library
local naughty = require("naughty")
local menubar = require("menubar")
local hotkeys_popup = require("awful.hotkeys_popup")

-- Menus/Widgets
local appmenu = load_widget("appmenu")
local calendar = load_widget("calendar")
local switcher = load_widget("switcher")
local shutdown = load_widget("shutdown")
local notifications = load_widget("notifications")
appmenu_init()
shutdown_init()

-- Config settings
local config = require("config")


-- {{{ Default Applications
compositor = config.compositor
terminal = config.terminal
editor = config.editor
web_browser = config.web_browser
bluetooth = config.bluetooth
-- }}}

-- {{{ Settings
modkey = config.modkey
screenshot_path = config.screenshot_path
-- }}}


-- Enable hotkeys help widget for VIM and other apps
-- when client with a matching name is opened:
require("awful.hotkeys_popup.keys")

-- Launch picom (compositor)
awful.spawn(compositor)

-- {{{ Autostart
awful.spawn.with_shell(
    'if (xrdb -query | grep -q "^awesome\\.started:\\s*true$"); then exit; fi;' ..
    'xrdb -merge <<< "awesome.started:true";' ..
    'dex --environment Awesome --autostart --search-paths "${XDG_CONFIG_HOME:-$HOME/.config}/autostart:${XDG_CONFIG_DIRS:-/etc/xdg}/autostart";'
	)
--- }}}

-- {{{ Error handling
-- Check if awesome encountered an error during startup and fell back to
-- another config (This code will only ever execute for the fallback config)
if awesome.startup_errors then
    naughty.notify({ preset = naughty.config.presets.critical,
                     title = "Oops, there were errors during startup!",
                     text = awesome.startup_errors })
end

-- Handle runtime errors after startup
do
    local in_error = false
    awesome.connect_signal("debug::error", function (err)
        -- Make sure we don't go into an endless error loop
        if in_error then return end
        in_error = true

        naughty.notify({ preset = naughty.config.presets.critical,
                         title = "Error in rc",
                         text = tostring(err) })
        in_error = false
    end)
end
-- }}}

naughty.config.defaults.timeout = 0

--- {{{ App Menu

-- Create the app menu popup
appmenu_data.popup = awful.popup {
    widget = appmenu_create(),
    border_color = beautiful.border_focus,
    border_width = beautiful.border_width,
    placement = awful.placement.centered,
    ontop = true,
    visible = false,
    hide_on_right_click = true,
    shape = function(cr, width, height)
        gears.shape.rounded_rect(cr, width, height, 8)
    end,
    minimum_width = dpi(400),
    maximum_width = dpi(400),
    maximum_height = dpi(600)
}

--- }}}


-- {{{ Drawing functions for wibar
-- Makes an empty space widget with the given width
function make_spacer(width)
    return wibox.widget {
        left = width,
        widget  = wibox.container.margin
    }
end

-- Makes a filled rounded rectangle shape for the taglist and tasklist
function taglist_dot_sel(size, fg)
    local surface = cairo.ImageSurface.create("ARGB32", size, size)
    local cr = cairo.Context.create(surface)
    -- Round the center and radius to avoid sub-pixel positioning
    local center = math.floor(size / 2 + 0.5)
    local radius = math.floor(size / 2.0)
    cr:arc(center, center, radius, 0, 2 * math.pi)
    cr:set_source(gears.color(fg))
    cr.antialias = cairo.Antialias.BEST
    cr:fill()
    return surface
end

-- Makes an empty rounded rectangle shape for the taglist and tasklist
function taglist_dot_unsel(size, fg)
    local surface = cairo.ImageSurface.create("ARGB32", size, size)
    local cr = cairo.Context.create(surface)
    local line_width = dpi(5)
    cr:arc(size / 2, size / 2, size / 2 - line_width, math.rad(0), math.rad(360))
    cr:set_source(gears.color(fg))
    cr.antialias = cairo.Antialias.BEST
    cr:set_line_width(line_width)
    cr:stroke()
    return surface
end

-- }}}


-- Stores the wibox
globalWibox = nil
wiboxEnabled = true


-- {{{ Bisect the monitor into 2 screens (for ultrawide monitors)
if (config.split_ultrawide) then
	local geo = screen[1].geometry
	local full_screen_width = geo.width
	local full_screen_height = geo.height
	if full_screen_width / full_screen_height > 16.0/9.0 then
		local new_width = math.ceil(geo.width / 2)
		local new_width2 = geo.width - new_width
		screen[1]:fake_resize(geo.x, geo.y, new_width, geo.height)
		screen.fake_add(geo.x + new_width, geo.y, new_width2, geo.height)
	end
end
-- }}}

-- Disable mouse snapping to edge
awful.mouse.snap.edge_enabled = false


-- {{{ Variable definitions
-- Themes define colours, icons, font and wallpapers.
beautiful.init(config_dir .. "theme.lua")
-- Use higher-res icons
awesome.set_preferred_icon_size(64)

-- This is used later as the default terminal and editor to run.
editor_cmd = terminal .. " -e " .. editor

-- Table of layouts to cover with awful.layout.inc, order matters.
awful.layout.layouts = {
    -- awful.layout.suit.floating,
    awful.layout.suit.tile,
    -- awful.layout.suit.tile.left,
    -- awful.layout.suit.tile.bottom,
    -- awful.layout.suit.tile.top,
    -- awful.layout.suit.fair,
    -- awful.layout.suit.fair.horizontal,
    -- awful.layout.suit.spiral,
    -- awful.layout.suit.spiral.dwindle,
    -- awful.layout.suit.max,
    -- awful.layout.suit.max.fullscreen,
    -- awful.layout.suit.magnifier,
    -- awful.layout.suit.corner.nw,
    -- awful.layout.suit.corner.ne,
    -- awful.layout.suit.corner.sw,
    -- awful.layout.suit.corner.se,
}
-- }}}


-- {{{ Menu
-- Create a launcher widget and a main menu
myawesomemenu = {
    { "hotkeys", function() hotkeys_popup.show_help(nil, awful.screen.focused()) end },
    { "manual", terminal .. " -e man awesome" },
    { "edit config", editor_cmd .. " " .. awesome.conffile },
    { "restart", awesome.restart },
    { "quit", function() awesome.quit() end },
}

mymainmenu = awful.menu({ items = {
    { "awesome", myawesomemenu, beautiful.awesome_icon },
    { "open terminal", terminal }
}
})

mylauncher = wibox.widget {
	{
		{
			{
				{
				    {
				        {
				            widget = awful.widget.launcher({ image = config_dir .. "theme-icons/arch_logo.png",
				            menu = mymainmenu})
				        },
				        strategy = "exact",
				        widget = wibox.container.constraint,
				    },
				    align = "center",
				    widget = wibox.container.place,
				},
				notifications.create_button(),
				spacing = dpi(0),
				layout = wibox.layout.fixed.horizontal
			},
			margins = dpi(4),
			left = dpi(6),
			widget = wibox.container.margin
		},
		shape = function(cr, width, height)
	            	gears.shape.rounded_rect(cr, width, height, dpi(6))
		        end,
		shape_border_width = 1,
		shape_border_color = beautiful.border_focus .. "88",
		bg = theme.tglauncher.bg,
		widget = wibox.container.background
	},
	top = dpi(6),
	bottom = dpi(6),
	left = dpi(0),
	right = dpi(4),
	widget = wibox.container.margin
}

-- Menubar configuration
menubar.utils.terminal = terminal -- Set the terminal for applications that require it
-- }}}

-- Keyboard map indicator and switcher
mykeyboardlayout = awful.widget.keyboardlayout()

-- {{{ Wibar

-- Create a wibox for each screen and add it
local taglist_buttons = gears.table.join(
awful.button({ }, 1, function(t) t:view_only() end),
awful.button({ modkey }, 1, function(t)
    if client.focus then
        client.focus:move_to_tag(t)
    end
end),
awful.button({ }, 3, awful.tag.viewtoggle),
awful.button({ modkey }, 3, function(t)
    if client.focus then
        client.focus:toggle_tag(t)
    end
end),
awful.button({ }, 4, function(t) awful.tag.viewnext(t.screen) end),
awful.button({ }, 5, function(t) awful.tag.viewprev(t.screen) end)
)

local tasklist_buttons = gears.table.join(
awful.button({ }, 1, function (c)
    if c == client.focus then
        c.minimized = true
    else
        c.first_tag:view_only()
        c:emit_signal(
        "request::activate",
        "tasklist",
        {raise = true}
    )
end
end),
awful.button({ }, 3, function()
    awful.menu.client_list({ theme = { width = 250 } })
end),
awful.button({ }, 4, function ()
    awful.client.focus.byidx(1)
end),
awful.button({ }, 5, function ()
    awful.client.focus.byidx(-1)
end))

local function set_wallpaper(s)
    -- Wallpaper
    if beautiful.wallpaper then
        local wallpaper = beautiful.wallpaper
        -- If wallpaper is a function, call it with the screen
        if type(wallpaper) == "function" then
            wallpaper = wallpaper(s)
        end
        gears.wallpaper.maximized(wallpaper, s, true)
    end
end

-- Re-set wallpaper when a screen's geometry changes (e.g. different resolution)
screen.connect_signal("property::geometry", set_wallpaper)

awful.screen.connect_for_each_screen(function(s)
    -- Wallpaper
    set_wallpaper(s)

    -- Each screen has its own tag table.
    awful.tag({ "1", "2", "3", "4", "5", "6", "7", "8", "9" }, s, awful.layout.layouts[1])

    -- Create a promptbox for each screen
    s.mypromptbox = awful.widget.prompt()
    -- Create an imagebox widget which will contain an icon indicating which layout we're using.
    -- We need one layoutbox per screen.
    s.mylayoutbox = awful.widget.layoutbox(s)
    s.mylayoutbox:buttons(gears.table.join(
    awful.button({ }, 1, function () awful.layout.inc( 1) end),
    awful.button({ }, 3, function () awful.layout.inc(-1) end),
    awful.button({ }, 4, function () awful.layout.inc( 1) end),
    awful.button({ }, 5, function () awful.layout.inc(-1) end)))
    -- Create a taglist widget
    local tag_shape = function(cr, width, height)
        gears.shape.rounded_rect(cr, width, height, 4)
    end

   	s.mytaglist = awful.widget.taglist {
        screen  = s,
        filter  = awful.widget.taglist.filter.all,
        buttons = taglist_buttons,
        widget_template =
        {
            {
                {
                    {
                        {
                            {
                                {
                                    {
                                        id = "icon_role",
                                        widget = wibox.widget.imagebox,
                                    },
                                    strategy = "exact",
                                    width = dpi(7),
                                    widget = wibox.container.constraint
                                },
                                margins = dpi(5),
                                widget = wibox.container.margin,
                            },
                            halign = "left",
                            valign = "top",
                            widget = wibox.container.place,
                        },
                        {
                            {
                                {
                                    id     = 'text_role',
                                    widget = wibox.widget.textbox,
                                },
                                align = "center",
                                widget = wibox.container.place,
                            },
                            left = dpi(-2),
                            widget = wibox.container.margin
                        },
                        layout = wibox.layout.fixed.horizontal,
                    },
                    id     = 'background_role',
                    widget = wibox.container.background,
                },
                strategy = "exact",
                width = dpi(42),
                widget = wibox.container.constraint
            },
            top = dpi(5),
            bottom = dpi(5),
            widget = wibox.container.margin,
            update_callback = function(self, tg, index, objects)
	           	local selected = false
	           	for _, ta in pairs(awful.screen.focused().selected_tags) do
	          	    if ta == tg then
	                    selected = true
	               	end
	           	end
	            
	           	local background = self:get_children_by_id('background_role')[1]
	           	local imagebox = self:get_children_by_id('icon_role')[1]
	            
	            -- Handle tag backgrounds
                gears.timer.start_new(0.01, function()
					if tg.urgent then
	                    background.bg = gears.color.create_pattern({
	                        type = "radial",
	                        from = { dpi(9), dpi(9), 0 },    -- Starting circle: x, y, radius
	                        to = { dpi(9), dpi(9), dpi(30) },     -- Ending circle: x, y, radius
	                        stops = {
	                            { 0, beautiful.taglist_urgent .. "88" },
								{ 1, beautiful.taglist_urgent .. "28" }
	                        }
	                    })
					end
					return false
                end)
	            
	           	-- Update focus dot
	           	if (tg:clients()[1] ~= nil) then
					if (selected) then
	                   	imagebox.image = taglist_dot_sel(dpi(10), beautiful.taglist_dot .. "f0")
	               	else
	                   	imagebox.image = taglist_dot_unsel(dpi(50), tg.urgent and beautiful.taglist_dot .. "ff" or beautiful.taglist_dot .. "a0")
	               	end
	           	else
	               	imagebox.image = nil
	           	end
	       	end
       	}
   	}

    -- Create a tasklist widget
    s.mytasklist = awful.widget.tasklist {
        screen  = s,
        filter  = awful.widget.tasklist.filter.currenttags,
        layout   = {
            layout  = wibox.layout.fixed.horizontal
        },
        widget_template =
        {
            {
                {
                    {
                        {
                            {
                                {
                                    {
                                        id     = 'icon_role',
                                        widget = wibox.widget.imagebox,
                                    },
                                    strategy = exact,
                                    height = dpi(30),
                                    widget  = wibox.container.constraint,
                                },
                                valign = "center",
                                widget = wibox.container.place,
                            },
                            left = dpi(-5),
                            right = dpi(8),
                            widget = wibox.container.margin,
                        },
                        {
                            id     = 'text_role',
                            widget = wibox.widget.textbox,
                        },
                        layout = wibox.layout.fixed.horizontal,
                    },
                    left  = dpi(16),
                    right = dpi(16),
                    widget = wibox.container.margin
                },
                strategy = "max",
                forced_width = dpi(300),
                widget = wibox.container.constraint,
            },
            id     = 'background_role',
            widget = wibox.container.background,
            create_callback = function(self, client, index, objects)
                self:connect_signal('widget::redraw_needed', function()
                    iconWidget = self:get_children_by_id('icon_role')[1]
                    if (client.minimized) then
                        iconWidget.opacity = 0.3
                    else
                        iconWidget.opacity = 1
                    end
                end)
            end
        },
        buttons = tasklist_buttons
    }

	-- Create a textclock widget
	s.mytextclock = wibox.widget {
        {
            {
                {
                    {
                        format = string.format(
                            '<span foreground="%s">%%a, %%b %%d</span>',
                            theme.clock.fg
                        ),
                        font = font_with_size(dpi(10)),
                        widget = wibox.widget.textclock
                    },
                    top = dpi(-1),
                    widget = wibox.container.margin
                },
                halign = "right",
                widget = wibox.container.place,
            },
            {
                {
                    format = string.format(
                        '<span foreground="%s">%%I:%%M %%p</span>',
                        theme.clock.fg
                    ),
                    font = font_with_size(dpi(12)),
                    widget = wibox.widget.textclock
                },
                halign = "right",
                widget = wibox.container.place,
            },
            layout = wibox.layout.align.vertical
        },
        align = "center",
        widget = wibox.container.place,
    }

	-- Create a calendar instance for this screen
    local screen_calendar = calendar.new()
    screen_calendar:attach(s.mytextclock, s)

    local squircle = function(cr, width, height)
        gears.shape.rounded_rect(cr, width, height, 4)
    end

    -- Create the wibox
    s.mywibox = awful.wibar({ position = "top", screen = s, bg = beautiful.bg_normal})

    -- Initialize systray
	if s == screen.primary then
	    s.mysystray = wibox.widget.systray()
	else
	    s.mysystray = wibox.widget.textbox("")
	end

	-- Create systray
	if s == screen.primary then
	    local systray_container = wibox.widget {
	        {
	            s.mysystray,
	            top = dpi(13),
	            bottom = dpi(13),
	            left = dpi(10),
	            right = dpi(10),
	            widget = wibox.container.margin
	        },
	        bg = beautiful.bg_systray,
	        shape = function(cr, width, height)
	            gears.shape.rounded_rect(cr, width, height, dpi(10))
	        end,
	        shape_border_width = 1,
	        shape_border_color = beautiful.border_focus .. "aa",
	        visible = false,
	        widget = wibox.container.background
	    }
	    systray_widget = systray_container
	    
	    -- Hide systray widget if it is empty
	    local check_visibility = function()
	        systray_container.visible = awesome.systray() > 0
	    end
	    
	    awesome.connect_signal("systray::update", check_visibility)
	    check_visibility()
	else
		systray_widget = nil
	end

	-- Add widgets to the wibox
    s.mywibox:setup({
        layout = wibox.layout.align.horizontal,
        -- Left widgets
        {
            layout = wibox.layout.fixed.horizontal,
            make_spacer(dpi(8)),
            mylauncher,
            make_spacer(dpi(8)),
            s.mytaglist,
            make_spacer(10),
            create_divider(1, dpi(8)),
            make_spacer(dpi(10)),
            -- Tasklist
            {
                {
                    widget = s.mytasklist,
                },
                widget = wibox.container.margin,
                top = 3,
                bottom = 3
            },
            s.mypromptbox,
        },
        -- Middle widgets
        nil,
        -- Right widgets
        {
            layout = wibox.layout.fixed.horizontal,
            make_spacer(dpi(12)),
            {
                systray_widget,
                top = dpi(4),
                bottom = dpi(4),
                widget = wibox.container.margin
            },
            make_spacer(dpi(12)),
            create_divider(1, dpi(8)),
            make_spacer(dpi(12)),
            s.mytextclock,  -- Use the screen-specific textclock
            make_spacer(dpi(12)),
            create_divider(1, dpi(4)),
        },
    })
    globalWibox = s.mywibox
end)
-- }}}

-- {{{ Mouse bindings
root.buttons(gears.table.join(
awful.button({ }, 3, function () mymainmenu:toggle() end),
awful.button({ }, 4, awful.tag.viewnext),
awful.button({ }, 5, awful.tag.viewprev)
))
-- }}}

-- {{{ Key bindings
globalkeys = gears.table.join(
awful.key({ "Control", modkey, "Mod1"}, "q", function () awful.spawn('shutdown now') end,
{description="shutdown", group="awesome"}),
awful.key({}, "Print", take_screenshot,
{description="screenshot", group="awesome"}),
awful.key({ modkey,           }, "s",      hotkeys_popup.show_help,
{description="show help", group="awesome"}),
awful.key({ modkey,           }, "Left",   awful.tag.viewprev,
{description = "view previous", group = "tag"}),
awful.key({ modkey,           }, "Right",  awful.tag.viewnext,
{description = "view next", group = "tag"}),
awful.key({ modkey,           }, "Escape", awful.tag.history.restore,
{description = "go back", group = "tag"}),

awful.key({ modkey,           }, "j",
function ()
    awful.client.focus.byidx( 1)
end,
{description = "focus next by index", group = "client"}
),
awful.key({ modkey,           }, "k",
function ()
    awful.client.focus.byidx(-1)
end,
{description = "focus previous by index", group = "client"}
),
awful.key({ modkey,           }, "a", function () mymainmenu:show() end,
{description = "show main menu", group = "awesome"}),

-- Layout manipulation
awful.key({ modkey, "Shift"   }, "j", function () awful.client.swap.byidx(  1)    end,
{description = "swap with next client by index", group = "client"}),
awful.key({ modkey, "Shift"   }, "k", function () awful.client.swap.byidx( -1)    end,
{description = "swap with previous client by index", group = "client"}),
awful.key({ modkey, "Control" }, "j", function () awful.screen.focus_relative( 1) end,
{description = "focus the next screen", group = "screen"}),
awful.key({ modkey, "Control" }, "k", function () awful.screen.focus_relative(-1) end,
{description = "focus the previous screen", group = "screen"}),
awful.key({ modkey }, "u", awful.client.urgent.jumpto,
{description = "jump to urgent client", group = "client"}),
--[[ awful.key({  }, "Super_L", function()
    awful.keygrabber {
        keybindings = {
            {{ }, "Super_L", function () end}
        },
        stop_key           = "Super_L",
        stop_event         = "release",
        start_callback     = function () naughty.notify{text = "ddd"} end,
        stop_callback      = function ()
            wiboxEnabled = not wiboxEnabled
            for s in screen do
                s.mywibox.visible = wiboxEnabled
            end
            naughty.notify({text="test2"})
        end,
        export_keybindings = true,
        mask_event_callback = false
    }
end,
{description = "toggle the wibar", group = "screen"}), --]]
awful.key({ modkey }, "Tab", function() switcher.show() end,
{description = "task switcher", group = "client"}),

-- Standard program
awful.key({ modkey,           }, "Return", function () awful.spawn(terminal) end,
{description = "open a terminal", group = "launcher"}),
awful.key({ modkey,           }, "w", function () awful.spawn(web_browser) end,
{description = "open web browser", group = "launcher"}),
awful.key({ modkey }, "b", function() awful.spawn(bluetooth) end,
{description = "open bluetooth menu", group = "client"}),
awful.key({ modkey, "Control" }, "r", awesome.restart,
{description = "reload awesome", group = "awesome"}),
awful.key({ modkey, "Control"   }, "q", shutdown_toggle,
{description = "quit awesome", group = "awesome"}),

awful.key({ modkey,           }, "]",     function () awful.tag.incmwfact( 0.05)          end,
              {description = "increase master width factor", group = "layout"}),
    awful.key({ modkey,           }, "[",     function () awful.tag.incmwfact(-0.05)          end,
              {description = "decrease master width factor", group = "layout"}),
    awful.key({ modkey, "Shift"   }, "h",     function () awful.tag.incnmaster( 1, nil, true) end,
              {description = "increase the number of master clients", group = "layout"}),
    awful.key({ modkey, "Shift"   }, "l",     function () awful.tag.incnmaster(-1, nil, true) end,
              {description = "decrease the number of master clients", group = "layout"}),
    awful.key({ modkey, "Control" }, "h",     function () awful.tag.incncol( 1, nil, true)    end,
              {description = "increase the number of columns", group = "layout"}),
    awful.key({ modkey, "Control" }, "l",     function () awful.tag.incncol(-1, nil, true)    end,
              {description = "decrease the number of columns", group = "layout"}),

    awful.key({ modkey, "Control" }, "n",
              function ()
                  local c = awful.client.restore()
                  -- Focus restored client
                  if c then
                    c:emit_signal(
                        "request::activate", "key.unminimize", {raise = true}
                    )
                  end
              end,
              {description = "restore minimized", group = "client"}),

    -- Prompt
    awful.key({ modkey },            "r",     function () awful.screen.focused().mypromptbox:run() end,
              {description = "run prompt", group = "launcher"}),

    awful.key({ modkey }, "l",
              function ()
                  awful.prompt.run {
                    prompt       = "Run Lua code: ",
                    textbox      = awful.screen.focused().mypromptbox.widget,
                    exe_callback = awful.util.eval,
                    history_path = awful.util.get_cache_dir() .. "/history_eval"
                  }
              end,
              {description = "lua execute prompt", group = "awesome"}),
    -- Menubar
    awful.key({ modkey }, "d", function() appmenu_toggle() end,
    	{description = "show application menu", group = "launcher"})
)

clientkeys = gears.table.join(
    awful.key({ modkey, "Shift"   }, "f",
        function (c)
            c:raise()
            c.fullscreen = not c.fullscreen
            set_focus_to_mouse()
        end,
        {description = "toggle fullscreen", group = "client"}),

    awful.key({ modkey, "Control"   }, "f",
        function (c)
        	c.ontop = not c.ontop
        	c.floating = c.ontop
        	if (c.ontop) then
		    	c.screen = screen[1]
		        c.x = 0
		        c.y = 0
		        c.width = full_screen_width
		        c.height = full_screen_height
		        set_focus_to_mouse()
            end
        end,
        {description = "toggle ultra fullscreen", group = "client"}),

    awful.key({ modkey,           }, "q",
        function (c)
            c:kill()
            set_focus_to_mouse()
        end,
        {description = "close", group = "client"}),

    awful.key({ modkey            }, "space",
    function (c)
        c.floating = not c.floating
        c.ontop = c.floating
        if (c.floating) then
            c.maximized = false
        end
        if (c.floating) then
            c:raise()
            -- Set the window position to the cursor position, minding the workable area
            local geo = c.screen:get_bounding_geometry({honor_padding  = true, honor_workarea = true})
            local winWidth = geo.width / 2
            local winHeight = geo.height / 2
            c.width = winWidth
            c.height = winHeight
            c.x = mouse.coords().x - winWidth / 2
            c.y = mouse.coords().y - winHeight / 2
            clamp_window_bounds(c)
        end
        set_focus_to_mouse()
    end,
        {description = "toggle floating", group = "client"}),

    awful.key({ modkey, "Control" }, "Return", function (c) c:swap(awful.client.getmaster()) end,
              {description = "move to master", group = "client"}),

    awful.key({ modkey,           }, "o",      function (c) c:move_to_screen() end,
              {description = "swap screens", group = "client"}),

    awful.key({ modkey,           }, "t",      function (c) c.ontop = not c.ontop end,
              {description = "toggle keep on top", group = "client"}),

    awful.key({ modkey, "Shift"}, "q",
        function (c)
            c:unmanage()
        end,
        {description = "Forcefully unmanage a client", group = "client"}),

    awful.key({ modkey,           }, "x",
        function (c)
            c.minimized = true
            set_focus_to_mouse()
        end ,
        {description = "minimize", group = "client"}),

    awful.key({ modkey,           }, "f",
        function (c)
            c.maximized = not (c.maximized or c.fullscreen)
            c.fullscreen = false
            c:raise()
            set_focus_to_mouse()
        end ,
        {description = "(un)maximize", group = "client"}),
    awful.key({ modkey, "Control" }, "m",
        function (c)
            c.maximized_vertical = not c.maximized_vertical
            c:raise()
            set_focus_to_mouse()
        end ,
        {description = "(un)maximize vertically", group = "client"}),
    awful.key({ modkey, "Shift"   }, "m",
        function (c)
            c.maximized_horizontal = not c.maximized_horizontal
            c:raise()
            set_focus_to_mouse()
        end ,
        {description = "(un)maximize horizontally", group = "client"})
)

-- Bind all key numbers to tags.
-- Be careful: we use keycodes to make it work on any keyboard layout.
-- This should map on the top row of your keyboard, usually 1 to 9.
for i = 1, 9 do
    globalkeys = gears.table.join(globalkeys,
        -- View tag only.
        awful.key({ modkey }, "#" .. i + 9,
                  function ()
                        local screen = awful.screen.focused()
                        local tag = screen.tags[i]
                        if tag then
                           tag:view_only()
                           set_focus_to_mouse()
                        end
                  end,
                  {description = "view tag #"..i, group = "tag"}),
        -- Toggle tag display.
        awful.key({ modkey, "Control" }, "#" .. i + 9,
                  function ()
                      local screen = awful.screen.focused()
                      local tag = screen.tags[i]
                      if tag then
                         awful.tag.viewtoggle(tag)
                         set_focus_to_mouse()
                      end
                  end,
                  {description = "toggle tag #" .. i, group = "tag"}),
        -- Move client to tag.
        awful.key({ modkey, "Shift" }, "#" .. i + 9,
                  function ()
                      if client.focus then
                          local tag = client.focus.screen.tags[i]
                          if tag then
                              client.focus:move_to_tag(tag)
                              set_focus_to_mouse()
                          end
                     end
                  end,
                  {description = "move focused client to tag #"..i, group = "tag"}),
        -- Toggle tag on focused client.
        awful.key({ modkey, "Control", "Shift" }, "#" .. i + 9,
                  function ()
                      if client.focus then
                          local tag = client.focus.screen.tags[i]
                          if tag then
                              client.focus:toggle_tag(tag)
                              set_focus_to_mouse()
                          end
                      end
                  end,
                  {description = "toggle focused client on tag #" .. i, group = "tag"})
    )
end

clientbuttons = gears.table.join(
    awful.button({ }, 1, function (c)
        c:emit_signal("request::activate", "mouse_click", {raise = true})
    end),
    awful.button({ modkey }, 1, function (c)
        c:emit_signal("request::activate", "mouse_click", {raise = true})
        awful.mouse.client.move(c, 16)
    end),
    awful.button({ modkey }, 3, function (c)
        c:emit_signal("request::activate", "mouse_click", {raise = true})
        awful.mouse.client.resize(c)
    end)
)

-- Set keys
root.keys(globalkeys)
-- }}}

-- {{{ Rules
-- Rules to apply to new clients (through the "manage" signal).
awful.rules.rules = {
    -- All clients will match this rule.
    { rule = { },
      properties = { border_width = beautiful.border_width,
                     border_color = beautiful.border_normal,
                     focus = awful.client.focus.filter,
                     raise = true,
                     keys = clientkeys,
                     buttons = clientbuttons,
                     screen = awful.screen.preferred,
                     placement = awful.placement.no_overlap+awful.placement.no_offscreen
     }
    },

    -- Floating clients.
    { rule_any = {
        instance = {
          "DTA",  -- Firefox addon DownThemAll.
          "copyq",  -- Includes session name in class.
          "pinentry"
        },
        class = {
          "Arandr",
          "Blueman-manager",
          "Gpick",
          "Kruler",
          "MessageWin",  -- kalarm.
          "Sxiv",
          "Tor Browser", -- Needs a fixed window size to avoid fingerprinting by screen size.
          "Wpa_gui",
          "veromix",
          "xtightvncviewer"},

        -- Note that the name property shown in xprop might be set slightly after creation of the client
        -- and the name shown there might not match defined rules here.
        name = {
          "Event Tester",  -- xev.
        },
        role = {
          "AlarmWindow",  -- Thunderbird's calendar.
          "ConfigManager",  -- Thunderbird's about:config.
          "pop-up",       -- e.g. Google Chrome's (detached) Developer Tools.
        }
    }, properties = { floating = true }},

    -- Add titlebars to normal clients and dialogs
    { rule_any = { type = { "popup", "dialog" }, instance = { "zenity", "gcr-prompter" } },
    properties = { floating = true, ontop = true, focus = true, titlebars_enabled = false, placement = awful.placement.centered }},
    { rule_any = { instance = { "gnome-calculator" } },
    properties = { floating = true, ontop = true, focus = true, geometry = {height = dpi(800)}, screen = awful.screen.preferred, placement = awful.placement.centered}},
    { rule_any = { instance = { "qimgv", "f3d", "celluloid" } },
    properties = { floating = true, ontop = true, geometry = {height = dpi(600), width = dpi(1000)}, placement = awful.placement.top_right}},

    { rule = { name = "Application Menu" },
  	properties = { floating = true, ontop = true, sticky = true } }
}
-- }}}

-- {{{ Signals
-- Signal function to execute when a new client appears.
client.connect_signal("manage", function (c)

    if awesome.startup
      and not c.size_hints.user_position
      and not c.size_hints.program_position then
        -- Prevent windows from spawning off-screen
        awful.placement.no_offscreen(c)
    end

    -- Reset focus if new window isn't floating (because floating windows are usually popups)
    if (not c.floating) then
        set_focus_to_mouse()
    end
	c.sticky = false
end)

client.connect_signal("unmanage", function (c)
    -- Focus
    set_focus_to_mouse()
end)

-- Enable sloppy focus, so that focus follows mouse.
client.connect_signal("mouse::enter", function(c)
    if (client.focus ~= c 
		and not switcher_data.is_open 
		and not appmenu_data.wibox.visible 
		and not shutdown_data.wibox.visible) 
	then
        c:emit_signal("request::activate", "mouse_enter", {raise = false})
    end
end)

client.connect_signal("focus", function(c) c.border_color = beautiful.border_focus end)
client.connect_signal("unfocus", function(c) c.border_color = beautiful.border_normal end)
-- }}}

-- {{{ Random Wallpapers

function scanDir(directory, file_extensions)
    local i, fileList = 0, {}
    local cmd = string.format([[find %s -type f]], directory)
    
    -- Create a lookup table for extensions if provided
    local ext_lookup = {}
    if file_extensions then
        for _, ext in ipairs(file_extensions) do
            ext_lookup[ext:lower()] = true
        end
    end
    
    for filename in io.popen(cmd):lines() do
        -- If no extensions specified, include all files
        if not file_extensions then
            i = i + 1
            fileList[i] = filename
        else
            -- Extract the file extension
            local ext = filename:match("%.([^%.]+)$")
            if ext and ext_lookup[ext:lower()] then
                i = i + 1
                fileList[i] = filename
            end
        end
    end
    
    return fileList
end

-- Get the list of files from a directory. Must be all images or folders and non-empty.
local wallpaperList = scanDir(config_dir .. "wallpapers/", {"png", "jpg", "jpeg", "svg"})

if #wallpaperList > 0 then
    -- Apply a random wallpaper every 10 minutes
    changeTime = config.wallpaper_interval -- interval

    wallpaperTimer = timer { timeout = changeTime }
    local prevWallInt = -1
    wallpaperTimer:connect_signal("timeout", function()
        -- Seed the random generator
        math.randomseed(os.time())
        -- Select a random wallpaper that isn't the previous one
        local newWallInt = -1
        while(newWallInt == prevWallInt) do
            newWallInt = math.random(1, #wallpaperList)
        end
		
		local wallpaper = wallpaperList[newWallInt]
        -- Set the wallpaper
		if not wallpaper then
			naughty.notify({text = "could not find wallpaper " .. wallpaper})
		end
        gears.wallpaper.tiled(wallpaper, s)
    end)
    -- Trigger the wallpaper function once on startup
    wallpaperTimer:emit_signal("timeout")

    -- initial start when rc.lua is first run
    wallpaperTimer:start()
end
-- }}}