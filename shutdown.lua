local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local wibox = require("wibox")
local dpi = require("beautiful.xresources").apply_dpi
local naughty = require('naughty')

local config_dir = gears.filesystem.get_configuration_dir()
local icon_dir = config_dir .. "theme-icons/"
local theme = dofile(config_dir .. "theme.lua")
local util = require("util")

shutdown_data = {
    wibox = nil,
	overlay = nil,  -- Add this line
    current_index = 1,
    keygrabber = nil,
    actions = {
        {
            name = "Shut Down",
            icon = icon_dir .. "shutdown.png",
            command = "shutdown --now"
        },
        {
            name = "Restart",
            icon = icon_dir .. "restart.png",
            command = "reboot"
        },
        {
            name = "Sleep",
            icon = icon_dir .. "sleep.png",
            command = "systemctl suspend"
        }
    }
}

function create_action_button(action, index)
    local button = create_image_button({
        image_path = action.icon,
        fallback_text = "⚡",
        image_size = dpi(3),
        padding = dpi(16),
        button_size = dpi(64),
        opacity = 0.6,
        opacity_hover = 1,
        bg_color = theme.shutdown.button_bg,
        border_color = theme.shutdown.border .. "55",
        shape_radius = dpi(12),
        on_click = function()
            awful.spawn(action.command)
            shutdown_hide()
            return true
        end
    })

    local label = wibox.widget {
        {
            text = action.name,
            widget = wibox.widget.textbox,
            font = font_with_size(dpi(12)),
            align = 'center'
        },
        fg = theme.shutdown.fg,
        widget = wibox.container.background
    }

    local container = wibox.widget {
	    {
	        {
	            {  -- Add extra container to force center alignment
	                button,
	                layout = wibox.container.place,
	                halign = 'center'
	            },
	            label,
	            spacing = dpi(8),
	            layout = wibox.layout.fixed.vertical,
	        },
	        margins = dpi(8),
	        widget = wibox.container.margin
	    },
	    widget = wibox.container.background
	}

    -- Store update_focus function in container for later connection
    container.update_focus = function()
        if shutdown_data.current_index == index then
            button:emit_signal("button::focus")
        else
            button:emit_signal("button::unfocus")
            label.fg = theme.shutdown.fg
        end
    end

	button:connect_signal("button::focus", function()
		label.fg = theme.shutdown.fg_focus
	end)
	button:connect_signal("button::unfocus", function()
		label.fg = theme.shutdown.fg
	end)
    
    button:connect_signal("mouse::enter", function()
        shutdown_data.current_index = index
        shutdown_data.wibox:emit_signal("property::current_index")
    end)

    return container
end

function create_shutdown_widget()
    local buttons = wibox.widget {
        layout = wibox.layout.fixed.horizontal,
        spacing = dpi(16)
    }

    for i, action in ipairs(shutdown_data.actions) do
        buttons:add(create_action_button(action, i))
    end

    return wibox.widget {
        {
            buttons,
            margins = dpi(24),
            widget = wibox.container.margin
        },
        bg = theme.shutdown.bg,
        widget = wibox.container.background
    }
end

function create_overlay()
    -- Create fullscreen transparent overlay
    local overlay = wibox({
        x = 0,
        y = 0,
        visible = false,
        ontop = true,  -- Set back to true
        below = true,  -- This will place it below other ontop windows
        type = "utility",  -- Change type to utility
        bg = "#00000050",
    })
    
    -- Update overlay size and position when screen geometry changes
    function update_overlay()
        local screen_geom = mouse.screen.geometry
        local wibar = mouse.screen.mywibox
        local wibar_height = wibar and wibar.height or 0
        
        overlay.screen = mouse.screen
        overlay.x = screen_geom.x
        overlay.y = screen_geom.y + wibar_height
        overlay.width = screen_geom.width
        overlay.height = screen_geom.height - wibar_height
    end
    
    -- Connect to property changes
    mouse.screen:connect_signal("property::geometry", update_overlay)
    
    -- Initial setup
    update_overlay()
    
    return overlay
end

function handle_keyboard_navigation(mod, key)
    if key == "Escape" then
        shutdown_hide()
        return
    end

    if key == "Tab" then
        shutdown_data.current_index = shutdown_data.current_index % #shutdown_data.actions + 1
        shutdown_data.wibox:emit_signal("property::current_index")
        return
    end

    if key == "Return" then
        local action = shutdown_data.actions[shutdown_data.current_index]
        awful.spawn(action.command)
        shutdown_hide()
        return
    end

    if key == "Left" and shutdown_data.current_index > 1 then
        shutdown_data.current_index = shutdown_data.current_index - 1
        shutdown_data.wibox:emit_signal("property::current_index")
        return
    end

    if key == "Right" and shutdown_data.current_index < #shutdown_data.actions then
        shutdown_data.current_index = shutdown_data.current_index + 1
        shutdown_data.wibox:emit_signal("property::current_index")
        return
    end
end

function shutdown_init()
	shutdown_data.wibox = awful.popup {
        screen = mouse.screen,
        widget = create_shutdown_widget(),
        visible = false,
        ontop = true,
        type = "normal",
        width = dpi(400),
        height = dpi(160),
        bg = theme.shutdown.bg,
        border_color = theme.shutdown.border,
        border_width = 1,
        shape = function(cr, width, height)
            gears.shape.rounded_rect(cr, width, height, dpi(16))
        end
    }

	shutdown_data.overlay = create_overlay()

	-- Connect signals to all buttons after wibox creation
	local main_widget = shutdown_data.wibox.widget:get_children()[1] -- Get the margin container
	local buttons_layout = main_widget:get_children()[1] -- Get the buttons layout
	for _, button_container in ipairs(buttons_layout:get_children()) do
	    if button_container.update_focus then
	        shutdown_data.wibox:connect_signal("property::current_index", button_container.update_focus)
	        button_container.update_focus()
	    end
	end

    shutdown_data.keygrabber = awful.keygrabber {
        autostart = false,
        keypressed_callback = function(_, mod, key) handle_keyboard_navigation(mod, key) end,
        stop_callback = function()
            shutdown_data.wibox.visible = false
        end
    }

    return shutdown_data.wibox
end

function shutdown_show()
	if shutdown_data.overlay then
        update_overlay()
        shutdown_data.overlay.visible = true
    end

    if shutdown_data.wibox then
        shutdown_data.current_index = 1
        shutdown_data.wibox:emit_signal("property::current_index")
        shutdown_data.wibox.screen = mouse.screen
        awful.placement.centered(shutdown_data.wibox)
        shutdown_data.wibox.visible = true
        
        if client.focus then
            client.focus = nil
        end

        if shutdown_data.keygrabber then
            shutdown_data.keygrabber:start()
        end
    end
end

function shutdown_hide()
    if shutdown_data.wibox then
        shutdown_data.wibox.visible = false

		if shutdown_data.overlay then
            shutdown_data.overlay.visible = false
        end
        
        if shutdown_data.keygrabber then
            shutdown_data.keygrabber:stop()
        end

        local c = awful.mouse.client_under_pointer()
        if c then
            client.focus = c
            c:raise()
        end
    end
end

function shutdown_toggle()
    if shutdown_data.wibox and shutdown_data.wibox.visible then
        shutdown_hide()
    else
        shutdown_show()
    end
end

return {
    init = shutdown_init,
    show = shutdown_show,
    hide = shutdown_hide,
    toggle = shutdown_toggle
}