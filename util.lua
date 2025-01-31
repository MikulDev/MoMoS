local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local naughty = require("naughty")
local cairo = require("lgi").cairo
local wibox = require("wibox")
local dpi = require("beautiful.xresources").apply_dpi

local config_dir = gears.filesystem.get_configuration_dir()
local theme = dofile(config_dir .. "theme.lua")

local util = {}  -- Create the module table

function create_image_button(args)
    -- Default values merged with provided args
    args = args or {}
    local image_path = args.image_path
    local fallback_text = args.fallback_text or "⬡"
    local image_size = args.image_size or dpi(24)
    local padding = args.padding or dpi(6)
    local opacity = args.opacity or 1.0
	local opacity_hover = args.opacity_hover or opacity or 1
    local bg_color = args.bg_color or theme.appmenu.button_bg
    local border_color = args.border_color or theme.appmenu.border .. "55"
    local hover_bg = args.hover_bg or theme.appmenu.button_bg_focus
    local hover_border = args.hover_border or theme.appmenu.button_border_focus .. "33"
    local button_size = args.button_size
    local shape_radius = args.shape_radius or dpi(6)
    local on_click = args.on_click
    local on_right_click = args.on_right_click
    local on_ctrl_click = args.on_ctrl_click
    
    -- Create the image or fallback text widget
    local content_widget
    if image_path then
	    content_widget = wibox.widget {
	        {
	            image = image_path,
	            resize = true,
	            forced_width = image_size,
	            forced_height = image_size,
	            opacity = opacity,
	            widget = wibox.widget.imagebox,
	            id = 'icon'
	        },
	        margins = padding,
	        widget = wibox.container.margin
	    }
	else
        content_widget = wibox.widget {
            {
                text = fallback_text,
                font = beautiful.font .. " " .. tostring(math.floor(image_size * 0.83)),
                forced_width = image_size,
                forced_height = image_size,
                align = 'center',
                valign = 'center',
                widget = wibox.widget.textbox
            },
            margins = padding,
            widget = wibox.container.margin
        }
    end

    -- Create the button container
    local button = wibox.widget {
        content_widget,
        bg = bg_color,
        shape = function(cr, width, height)
            gears.shape.rounded_rect(cr, width, height, shape_radius)
        end,
        shape_border_width = 1,
        shape_border_color = border_color,
        widget = wibox.container.background
    }

    -- Add size constraints if specified
    if button_size then
        button.forced_width = button_size
        button.forced_height = button_size
    end

    -- Hover effects
	button:connect_signal("button::focus", function()
	    -- Change button colors
	    button.bg = hover_bg
	    button.shape_border_color = hover_border
	    -- Change icon opacity
	    local imagebox = button.widget:get_children_by_id('icon')[1]
	    if imagebox then imagebox.opacity = opacity_hover end
	end)
	
	button:connect_signal("button::unfocus", function()
	    -- Reset button colors
	    button.bg = bg_color
	    button.shape_border_color = border_color
	    -- Reset icon opacity
	    local imagebox = button.widget:get_children_by_id('icon')[1]
	    if imagebox then imagebox.opacity = opacity end
	end)

	button:connect_signal("mouse::enter", function()
	    button:emit_signal("button::focus")
	end)

	button:connect_signal("mouse::leave", function()
	    button:emit_signal("button::unfocus")
	end)

	add_hover_cursor(button)

    -- Click handlers
    local click_handlers = {}
    
    if on_click then
        table.insert(click_handlers, awful.button({}, 1, on_click))
    end
    
    if on_ctrl_click then
        table.insert(click_handlers, awful.button({ "Control" }, 1, on_ctrl_click))
    end
    
    if on_right_click then
        table.insert(click_handlers, awful.button({}, 3, on_right_click))
    end

    button:buttons(gears.table.join(table.unpack(click_handlers)))

    -- Add methods to update button properties
    function button:update_image(new_image)
        if content_widget.widget == wibox.widget.imagebox then
            content_widget.widget.image = new_image
        end
    end

    function button:update_text(new_text)
        if content_widget.widget == wibox.widget.textbox then
            content_widget.widget.text = new_text
        end
    end

    function button:update_colors(new_bg, new_border)
        button.bg = new_bg or bg_color
        button.shape_border_color = new_border or border_color
    end

    return button
end

function add_hover_cursor(widget)
    -- Store cursor state for this specific widget
    local widget_state = {
        old_cursor = nil,
        old_wibox = nil
    }

    widget:connect_signal("mouse::enter", function(w)
        if w == widget then
            local wibox = mouse.current_wibox
            widget_state.old_cursor = wibox.cursor
            widget_state.old_wibox = wibox
            wibox.cursor = "hand2"
        end
    end)
    
    widget:connect_signal("mouse::leave", function(w)
        if w == widget then
            if widget_state.old_wibox then
                widget_state.old_wibox.cursor = widget_state.old_cursor
                widget_state.old_wibox = nil
            end
        end
    end)
end

function math.clamp(val, lower, upper)
    if lower > upper then lower, upper = upper, lower end
    return math.max(lower, math.min(upper, val))
end

-- {{{ Window management functions

function get_focused_client()
   return client.focus
end

function clamp_window_bounds(c)
    local geo = c.screen:get_bounding_geometry({honor_padding  = true, honor_workarea = true})
    local winWidth = c.width
    local winHeight = c.height
    c.x = math.clamp(c.x, geo.x, geo.width - winWidth + geo.x)
    c.y = math.clamp(c.y, geo.y, geo.height - winHeight + geo.y)
end

-- Focuses the window currently under the mouse
-- Called when the window layout changes (window spawned/killed, tag changed, etc.)
function set_focus_to_mouse()
    if not (focusing or switcher_open) then
        local focus_timer = timer({ timeout = 0.1 })
        focus_timer:connect_signal("timeout", function()
            local c = awful.mouse.client_under_pointer()
            if not (c == nil) then
                client.focus = c
                c:raise()
            end
            focus_timer:stop()
        end)
        focus_timer:start()
    end
end
-- }}}

return util