local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local naughty = require("naughty")
local wibox = require("wibox")
local dpi = require("beautiful.xresources").apply_dpi
local config = require("config")
local util = require("util")

local config_dir = gears.filesystem.get_configuration_dir()
local theme = dofile(config_dir .. "theme.lua")

-- Initialize module
local notifications = {}

-- Notification storage
notifications.history = {}
notifications.popup = nil
notifications._label = nil
notifications._cached_button = nil

-- Scrolling state
local scroll_state = {
    start_idx = 1,
    items_per_page = 5,
}

do
    local in_error = false
    awesome.connect_signal("debug::error", function (err)
        -- Make sure we don't go into an endless error loop
        if in_error then return end
        in_error = true

        debug_log("[Error]: " .. tostring(err))
        in_error = false
    end)
end

-- Format the message to a single line with ellipsis
local function format_message(text, length)
    if not text then return "" end
    -- Remove newlines and extra spaces
    text = text:gsub("\n", " "):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
    -- Truncate if too long
    if #text > length then
        return text:sub(1, length) .. "..."
    end
    return text
end

-- Format timestamp into a 12-hour clock time
local function format_timestamp(timestamp)
    return os.date("%I:%M %p", timestamp):gsub("^0", "")  -- Remove leading zero from hour
end

local function wrap_notification(n)
	return {
        title = n.title or "",
        text = n.message or n.text or "",
        icon = n.app_icon or n.icon or "",
        timestamp = os.time(),
        notification = n,
        actions = n.actions
    }
end

local function add_notification(n)
    -- Create notification entry with the full notification object
    local notification = wrap_notification(n)
    
    -- Add to start of table
    table.insert(notifications.history, 1, notification)

    -- Update the list widget if it exists and is visible
    if notifications.popup and notifications.popup.visible then
        notifications.popup.widget = create_notification_list()
    end
    update_count()
end

local function remove_notification(n)
	for i, notif in ipairs(notifications.history) do
        if notif == n or notif.notification == n then
            table.remove(notifications.history, i)
            update_count()
            break
        end
    end
end

local function jump_to_client(n)
	local current_pos = mouse.coords()
	local jumped = false
	for _, c in ipairs(n.clients) do
		c.urgent = true
		if jumped then
			c:activate {
				context = "client.jumpto"
			}
		else
			c:jump_to()
			jumped = true
		end
	end
	mouse.coords{x = current_pos.x, y = current_pos.y}
end

-- Create a notification entry widget
local function create_notification_widget(n)
    -- Create close button
    local close_button = create_image_button({
        image_path = config_dir .. "theme-icons/close.png",
        image_size = dpi(16),
        padding = dpi(10),
        button_size = dpi(34),
        opacity = 0.5,
        opacity_hover = 1,
        bg_color = theme.notifications.close_button_bg,
        border_color = theme.notifications.button_border,
        hover_bg = theme.notifications.close_button_bg_focus,
        hover_border = theme.notifications.button_border_focus,
        shape_radius = dpi(0),
        on_click = function()
	        local index = nil
	        for i, notif in ipairs(notifications.history) do
	            if notif == n then 
	                index = i + 1
	                break
	            end
	        end
	        
	        remove_notification(n)
			debug_log("closed notification")	
	        
	        if notifications.popup and notifications.popup.visible then
	            notifications.popup.widget = create_notification_list()
	            
				-- Wait for UI to refresh
	            gears.timer.start_new(0.01, function()
                    if mouse.current_widget then
						-- Hover next widget
						mouse.current_widget:emit_signal("mouse::enter")
						-- Wait for close button to be visible
						gears.timer.start_new(0.01, function()
							-- Hover close button
							local cbutton = mouse.current_widget:get_children_by_id("close_button")[1]
							if cbutton then cbutton:emit_signal("mouse::enter") end
						end)
                    end
                    return false
                end)
	        end
	    end,
		id = "close_button"
    })

    -- Container for close button that's initially invisible
    local close_container = wibox.widget {
        {
            close_button,
            left = dpi(17),
            top = dpi(10),
            widget = wibox.container.margin
        },
        halign = "left",
        valign = "center",
        widget = wibox.container.place
    }
    close_container.visible = false
	-- Track hoving the notification close button
	close_hover = false
	close_button:connect_signal("mouse::enter", function()
		close_hover = true
	end)
	close_button:connect_signal("mouse::leave", function()
		close_hover = false
	end)

    -- Create the content
    local content = wibox.widget {
	    {
	        {
	            {
	                image = n.icon,
	                resize = true,
	                forced_width = config.notifications.icon_size,
	                forced_height = config.notifications.icon_size,
	                widget = wibox.widget.imagebox,
	            },
	            valign = "center",
	            widget = wibox.container.place
	        },
	        {
	            {
	                markup = "<b>" .. format_message(n.title, dpi(50)) .. "</b>",
	                font = font_with_size(dpi(12)),
	                align = "left",
	                forced_height = dpi(20),
	                widget = wibox.widget.textbox,
	                id = "notif_title"
	            },
	            {
	                {
	                    text = format_message(n.text, dpi(42)),
	                    font = font_with_size(dpi(12)),
	                    align = "left",
	                    forced_height = dpi(22),
	                    widget = wibox.widget.textbox,
	                    id = "notif_message"
	                },
	                nil,
	                {
	                    text = format_timestamp(n.timestamp),
	                    font = font_with_size(dpi(10)),
	                    widget = wibox.widget.textbox
	                },
	                forced_width = config.notifications.max_width,
	                layout = wibox.layout.align.horizontal
	            },
	            spacing = dpi(-2),
	            layout = wibox.layout.fixed.vertical
	        },
	        spacing = dpi(10),
	        layout = wibox.layout.fixed.horizontal
	    },
	    forced_width = config.notifications.max_width - dpi(20), -- Account for margins
	    widget = wibox.container.constraint
	}


    local bg_container = wibox.widget {
	    {
	        {
	            content,
	            margins = dpi(8),
	            widget = wibox.container.margin
	        },
	        fg = theme.notifications.button_fg,
	        bg = theme.notifications.notif_bg,
	        widget = wibox.container.background,
	        shape = function(cr, width, height)
	            gears.shape.rounded_rect(cr, width, height, dpi(6))
	        end,
	        shape_border_width = 1,
	        shape_border_color = theme.notifications.notif_border,
	        id = "notif_background"
	    },
	    top = dpi(10),
	    bottom = 0,
	    left = dpi(10),
	    right = dpi(10),
	    widget = wibox.container.margin
	}

    -- Main container with overlay
    local w = wibox.widget {
        bg_container,
        close_container,
        layout = wibox.layout.stack
    }

	w:buttons(gears.table.join(
        -- Left click: Execute action and remove from history
        awful.button({}, 1, function()
            if n.notification and close_hover == false then
                jump_to_client(n.notification)
                n.notification:destroy()
                
                -- Remove from history
                remove_notification(n)
                
                -- Hide the popup
                notifications.popup.visible = false
                
                -- Update the popup if still visible
                if notifications.popup and notifications.popup.visible then
                    notifications.popup.widget = create_notification_list()
                end
            end
        end)
    ))

	add_hover_cursor(w)
 
    -- Show/hide close button and change background on hover
    w:connect_signal("mouse::enter", function()
        close_container.visible = true
		local background = bg_container:get_children_by_id("notif_background")[1]
        background.bg = theme.notifications.notif_bg_hover
        background.shape_border_color = theme.notifications.notif_border_hover
    end)
    w:connect_signal("mouse::leave", function()
        close_container.visible = false
		local background = bg_container:get_children_by_id("notif_background")[1]
        background.bg = theme.notifications.notif_bg
        background.shape_border_color = theme.notifications.notif_border
    end)

    return w
end

-- Create the notification list widget
function create_notification_list()
    local list_layout = wibox.layout.fixed.vertical
	{
		spacing = 0
	}
	

    -- Calculate items per page based on max_height and entry_height
    scroll_state.items_per_page = math.floor(
        (config.notifications.max_height - dpi(20)) / config.notifications.entry_height
    )

    -- Create preview area
    local preview_area = wibox.widget {
        {
			{
	            {
	                id = "preview_content",
	                layout = wibox.layout.fixed.vertical,
	            },
	            margins = dpi(10),
	            widget = wibox.container.margin
			},
			layout = wibox.layout.fixed.horizontal
        },
        bg = theme.notifications.preview_bg,
        widget = wibox.container.background,
        visible = false
    }

    -- Create right side layout that wraps the preview
    local right_layout = wibox.widget {
        nil,
        preview_area,
        nil,
        expand = "none",
        layout = wibox.layout.align.vertical
    }

    -- Create a constraint container that will handle the width only
    local right_container = wibox.widget {
        right_layout,
        forced_width = config.notifications.max_width,
        visible = false,  -- Start hidden
        widget = wibox.container.constraint
    }

    -- Function to update preview
    local function update_preview(n)
        local content = wibox.widget {
            -- Heading with icon and title
            {
                {
                    {
                        image = n.icon,
                        resize = true,
                        forced_width = dpi(48),
                        forced_height = dpi(48),
                        widget = wibox.widget.imagebox,
                    },
                    valign = "center",
                    widget = wibox.container.place
                },
                {
                    markup = "<b>" .. (n.title or "") .. "</b>",
                    align = "left",
                    widget = wibox.widget.textbox
                },
                spacing = dpi(10),
                layout = wibox.layout.fixed.horizontal
            },
            -- Full message text
            {
                text = n.text,
                align = "left",
                wrap = "word",
                widget = wibox.widget.textbox
            },
            spacing = dpi(8),
            layout = wibox.layout.fixed.vertical
        }
        
        local preview_content = preview_area:get_children_by_id("preview_content")[1]
        preview_content:reset()
        preview_content:add(content)
        preview_area.visible = true
        right_container.visible = true
    end

    -- Function to clear preview
    local function clear_preview()
        local preview_content = preview_area:get_children_by_id("preview_content")[1]
        preview_content:reset()
        preview_area.visible = false
        right_container.visible = false
    end

    -- Create notification widgets with hover behavior
    local visible_widgets = {}
    local end_idx = math.min(scroll_state.start_idx + scroll_state.items_per_page - 1, #notifications.history)
    for i = scroll_state.start_idx, end_idx do
        local n = notifications.history[i]
        local w = create_notification_widget(n)
        
        -- Add hover behavior for preview
        w:connect_signal("mouse::enter", function()
            update_preview(n)
        end)
        w:connect_signal("mouse::leave", function()
            clear_preview()
        end)
        
        list_layout:add(w)
        table.insert(visible_widgets, w)
    end

    -- Create scroll controls if needed
    local scroll_controls = wibox.widget {
        layout = wibox.layout.align.horizontal
    }

    if scroll_state.start_idx > 1 then
        scroll_controls.first = wibox.widget {
            markup = "<b>▲</b>",
            align = "center",
            widget = wibox.widget.textbox
        }
        scroll_controls:buttons(gears.table.join(
            scroll_controls:buttons(),
            awful.button({}, 1, function()
                scroll_state.start_idx = math.max(1, scroll_state.start_idx - scroll_state.items_per_page)
                if notifications.popup then
                    notifications.popup.widget = create_notification_list()
                end
            end)
        ))
    end

    if end_idx < #notifications.history then
        scroll_controls.third = wibox.widget {
            markup = "<b>▼</b>",
            align = "center",
            widget = wibox.widget.textbox
        }
        scroll_controls:buttons(gears.table.join(
            scroll_controls:buttons(),
            awful.button({}, 1, function()
                scroll_state.start_idx = math.min(
                    #notifications.history,
                    scroll_state.start_idx + scroll_state.items_per_page
                )
                if notifications.popup then
                    notifications.popup.widget = create_notification_list()
                end
            end)
        ))
    end

    -- Create clear all button
    local clear_all_button = create_labeled_image_button({
        image_path = config_dir .. "theme-icons/close.png",
        label_text = "All",
        image_size = dpi(16),
        padding = dpi(8),
        opacity = 0.5,
        opacity_hover = 1,
        bg_color = theme.notifications.button_bg,
        border_color = theme.notifications.button_border,
        fg_color = theme.notifications.button_fg,
        hover_bg = theme.notifications.button_bg_focus,
        hover_border = theme.notifications.button_border_focus,
        hover_fg = theme.notifications.button_fg_focus,
        shape_radius = dpi(4),
        on_click = function()
            notifications.history = {}
            if notifications.popup then
                notifications.popup.widget = create_notification_list()
            end
			update_count()
        end
    })

    -- Combine list, clear button, and controls
    local list_widget = wibox.widget {
        list_layout,
        {
            {
                {
                    clear_all_button,
                    layout = wibox.layout.fixed.horizontal
                },
                halign = "left",
                widget = wibox.container.place
            },
            margins = dpi(10),
            widget = wibox.container.margin
        },
        scroll_controls,
        layout = wibox.layout.fixed.vertical,
        spacing = dpi(5)
    }

    -- Create the final layout
    local main_layout = wibox.layout.fixed.horizontal()
    main_layout.spacing = dpi(10)

    -- Add the list widget (with constraint)
    main_layout:add(wibox.widget {
        list_widget,
        forced_width = config.notifications.max_width + dpi(10),
        widget = wibox.container.constraint
    })

    -- Add right side container to main layout
    main_layout:add(right_container)

    return main_layout
end

-- Create the notification center button
function notifications.create_button()

    -- Create the label
    local label = wibox.widget {
        text = "0",
        font = font_with_size(math.floor(config.notifications.button_size * 0.75)),
        align = 'left',
        valign = 'center',
        widget = wibox.widget.textbox
    }

	local icon = wibox.widget {
        image = beautiful.notification_icon or config_dir .. "theme-icons/notification.png",
        resize = true,
        forced_width = config.notifications.button_size,
        forced_height = config.notifications.button_size,
        opacity = 0.5,
        widget = wibox.widget.imagebox
    }

    -- Create content
    local content = wibox.widget {
        {
            icon,
            margins = dpi(3),
            widget = wibox.container.margin
        },
        {
            label,
            right = dpi(3),
            widget = wibox.container.margin
        },
        layout = wibox.layout.fixed.horizontal
    }

    -- Create the button
    local button = wibox.widget {
        content,
        bg = theme.notifications.main_button_bg,
        shape = function(cr, width, height)
            gears.shape.rounded_rect(cr, width, height, dpi(4))
        end,
        fg = theme.notifications.button_fg,
        widget = wibox.container.background
    }

    -- Create the popup
    notifications.popup = awful.popup {
        widget = create_notification_list(),
        border_color = beautiful.border_focus,
        border_width = beautiful.border_width,
        ontop = true,
        visible = false,
        shape = function(cr, width, height)
            gears.shape.rounded_rect(cr, width, height, dpi(6))
        end,
        placement = function(d)
            awful.placement.top_left(d, {
                margins = {
                    top = beautiful.wibar_height + dpi(5),
                    left = dpi(5)
                },
                parent = mouse.screen
            })
        end
    }

	notifications.popup:connect_signal("mouse::leave", function()
        notifications.popup.visible = false
    end)

    -- Add hover effects
    button:connect_signal("mouse::enter", function()
        button.bg = theme.notifications.main_button_bg_focus
        icon.opacity = 1
        button.fg = theme.notifications.button_fg_focus
    end)

    button:connect_signal("mouse::leave", function()
        button.bg = theme.notifications.main_button_bg
        icon.opacity = 0.5
        button.fg = theme.notifications.button_fg
    end)

    -- Add all button handlers
    button:buttons(gears.table.join(
        -- Left click to toggle
        awful.button({}, 1, function()
            if #notifications.history == 0 then return end
            -- Reset scroll position when opening
            if not notifications.popup.visible then
                scroll_state.start_idx = 1
                notifications.popup.widget = create_notification_list()
            end
            -- Position popup on current screen
            notifications.popup.screen = mouse.screen
            notifications.popup.visible = not notifications.popup.visible
        end),
        -- Scroll up
        awful.button({}, 4, function()
            if notifications.popup.visible then
                scroll_state.start_idx = math.max(1, scroll_state.start_idx - 1)
                notifications.popup.widget = create_notification_list()
            end
        end),
        -- Scroll down
        awful.button({}, 5, function()
            if notifications.popup.visible then
                scroll_state.start_idx = math.min(
                    #notifications.history - scroll_state.items_per_page + 1,
                    scroll_state.start_idx + 1
                )
                notifications.popup.widget = create_notification_list()
            end
        end)
    ))

    -- Update function
    function update_count()
		gears.timer.start_new(0.1, function()
            label.text = tostring(#notifications.history)
            return false
        end)
    end

    -- Initial update
    update_count()

    local layout = wibox.widget {
        button,
        margins = dpi(4),
        widget = wibox.container.margin
    }

    return layout
end

-- Update count on notification dismissed
naughty.connect_signal("destroyed", update_count)

-- Add notification to map upon display
naughty.connect_signal("added", function(n)
    add_notification(n)
end)

-- Change mouse controls for notificaions
naughty.connect_signal("request::display", function(n)
	local function format_title(title)
		return string.format("<span font = \"%s\"><b>%s</b></span>", beautiful.font, title)
	end

	-- Store original title setter
    local orig_title_setter = n.set_title or n.title
    
    -- Override title setter
    n.set_title = function(self, new_title)
        local formatted_title = format_title(new_title)
        orig_title_setter(self, formatted_title)
    end
    
    -- Format initial title
    n.title = format_title(n.title)

	local box = naughty.layout.box {
        notification = n,
        widget_template = {
            {
                {
                    {
                        {
                            naughty.widget.icon,
                            {
                                naughty.widget.title,
                                naughty.widget.message,
                                spacing = dpi(5),
                                layout  = wibox.layout.fixed.vertical,
                            },
                            fill_space = true,
                            spacing    = dpi(18),
                            layout     = wibox.layout.fixed.horizontal,
                        },
                        spacing = dpi(10),
                        layout  = wibox.layout.fixed.vertical,
                    },
                    margins = beautiful.notification_margin,
                    widget  = wibox.container.margin,
                },
                id     = "background_role",
                widget = naughty.container.background,
            },
            strategy = "max",
            width    = beautiful.notification_max_width,
            widget   = wibox.container.constraint,
        }
    }

	if config.notifications.timeout then
        gears.timer.start_new(config.notifications.timeout, function()
            if box and not box._private.is_destroyed then
                box.visible = false
            end
            return false
        end)
    end

    if box then
        box.buttons = gears.table.join(
            -- Left-click triggers notification action
            awful.button({}, 1, function()
                -- action 2 = dismissed by user (triggers)
                n:destroy(2)
                jump_to_client(n)
                remove_notification(n)
            end),
            -- Right-click dismisses notification
            awful.button({}, 3, function()
                -- action 1 = expired (no trigger)
                n:destroy(1)
                remove_notification(n)
            end))
    end
end)

return notifications