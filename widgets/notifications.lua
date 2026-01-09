--[[
    Notification History System for Awesome WM

    This module provides:
    - A notification history viewer with scrolling and preview
    - Persistent storage (survives restarts)
    - Proper notification lifecycle management (no gaps)
    - Click-to-focus functionality

    Key design decisions:
    - Notifications are allowed to expire/destroy naturally
    - Only serializable data is stored (no live object references)
    - History is saved to disk as JSON for persistence
    - App identification is stored separately for jump-to-client
]]

local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local naughty = require("naughty")
local wibox = require("wibox")
local dpi = require("beautiful.xresources").apply_dpi
local config = require("config")
local util = require("util")

local config_dir = gears.filesystem.get_configuration_dir()
local theme = load_util("theme")

--------------------------------------------------------------------------------
-- Debug Log
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- Module State
--------------------------------------------------------------------------------

local notifications = {
    history = {},
    popup = nil,
    button = nil,
    hovered = false,
    current_preview = nil,
}

-- File path for persistent storage
local history_file = gears.filesystem.get_cache_dir() .. "notification_history.json"

-- Scroll state
local scroll_state = {
    start_idx = 1,
    items_per_page = 5,
}

-- Debounce timer for saving
local save_timer = nil

-- Close button hover state (local to avoid global)
local close_button_hovered = false

--------------------------------------------------------------------------------
-- Persistence Functions
--------------------------------------------------------------------------------

--- Serialize history to JSON and save to disk
local function save_history()
    -- Cancel any pending save
    if save_timer then
        save_timer:stop()
        save_timer = nil
    end

    -- Debounce: wait 1 second before actually saving
    save_timer = gears.timer.start_new(1, function()
        local file = io.open(history_file, "w")
        if file then
            -- Only save serializable fields
            local data = {}
            for _, entry in ipairs(notifications.history) do
                table.insert(data, {
                    title = entry.title,
                    text = entry.text,
                    icon = entry.icon,
                    timestamp = entry.timestamp,
                    app_class = entry.app_class,
                    app_name = entry.app_name,
                })
            end

            -- Simple JSON encoding (Awesome doesn't have json by default)
            local json = "["
            for i, entry in ipairs(data) do
                if i > 1 then json = json .. "," end
                json = json .. string.format(
                    '{"title":%q,"text":%q,"icon":%q,"timestamp":%d,"app_class":%q,"app_name":%q}',
                    entry.title or "",
                    entry.text or "",
                    entry.icon or "",
                    entry.timestamp or 0,
                    entry.app_class or "",
                    entry.app_name or ""
                )
            end
            json = json .. "]"

            file:write(json)
            file:close()
        end
        save_timer = nil
        return false
    end)
end

--- Load history from disk
local function load_history()
    local file = io.open(history_file, "r")
    if not file then return end

    local content = file:read("*all")
    file:close()

    if not content or content == "" then return end

    -- Simple JSON parsing for our specific format
    notifications.history = {}

    for entry_json in content:gmatch('{[^}]+}') do
        local entry = {}
        entry.title = entry_json:match('"title":"([^"]*)"') or ""
        entry.text = entry_json:match('"text":"([^"]*)"') or ""
        entry.icon = entry_json:match('"icon":"([^"]*)"') or ""
        entry.timestamp = tonumber(entry_json:match('"timestamp":(%d+)')) or 0
        entry.app_class = entry_json:match('"app_class":"([^"]*)"') or ""
        entry.app_name = entry_json:match('"app_name":"([^"]*)"') or ""

        -- Unescape basic escape sequences
        entry.title = entry.title:gsub("\\n", "\n"):gsub('\\"', '"')
        entry.text = entry.text:gsub("\\n", "\n"):gsub('\\"', '"')

        table.insert(notifications.history, entry)
    end
end

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

--- Format timestamp to 12-hour clock
local function format_timestamp(timestamp)
    return os.date("%I:%M %p", timestamp):gsub("^0", "")
end

--- Update the notification count on the button
local function update_count()
    if notifications.button then
        notifications.button:update_text(tostring(#notifications.history))
    end
end

--- Refresh the popup widget if visible
local function refresh_popup()
    if notifications.popup and notifications.popup.visible then
        notifications.popup.widget = notifications.create_list()
    end
end

--- Extract notification data into a serializable table
local function extract_notification_data(n)
    local app_class = ""
    local app_name = ""

    -- Try to get app info from clients
    if n.clients and #n.clients > 0 then
        local client = n.clients[1]
        app_class = client.class or ""
        app_name = client.name or ""
    end

    -- Fall back to app_name from notification
    if app_name == "" then
        app_name = n.app_name or ""
    end
    
    return {
        title = n.title or "",
        text = n.message or n.text or "",
        icon = n.app_icon or n.icon or "",
        timestamp = os.time(),
        app_class = app_class,
        app_name = app_name,
    }
end

--- Check if a notification should be stored based on config
local function should_store_notification(n)
    if not config.notifications or not config.notifications.dont_store then
        return true
    end

    for _, entry in ipairs(config.notifications.dont_store) do
        -- Don't store if "no name" is blocked and notif has no owner
        if entry == "" and (not n.clients or #n.clients == 0) then
            return false
        end

        -- Don't store if notif's owner matches the blocklist
        if n.clients then
            for _, c in ipairs(n.clients) do
                if c.class then
                    if entry == "" then
                        if c.class == entry then return false end
                    elseif string.find(c.class:lower(), entry:lower()) then
                        return false
                    end
                end
            end
        end
    end

    return true
end

--- Add a notification to history
local function add_to_history(n)
    if not should_store_notification(n) then
        return
    end

    local entry = extract_notification_data(n)
    table.insert(notifications.history, 1, entry)

    -- Limit history size
    local max_history = (config.notifications and config.notifications.max_history) or 100
    while #notifications.history > max_history do
        table.remove(notifications.history)
    end

    update_count()
    refresh_popup()
    save_history()
end

--- Remove a notification from history by index
local function remove_from_history(index)
    if index and index > 0 and index <= #notifications.history then
        table.remove(notifications.history, index)
        update_count()
        save_history()
        return true
    end
    return false
end

--- Find and focus a client by app class/name
local function jump_to_app(entry)
    if not entry then return false end

    local app_class = entry.app_class or ""
    local app_name = entry.app_name or ""
    local found = false

    -- Search for matching client
    for _, c in ipairs(client.get()) do
        local class_match = app_class ~= "" and c.class and
                           c.class:lower():find(app_class:lower())
        local name_match = app_name ~= "" and c.name and
                          c.name:lower():find(app_name:lower())

        if class_match or name_match then
            c:jump_to()
            found = true
            break
        end
    end

    -- If no client found, try to launch the app
    if not found and app_class ~= "" then
        awful.spawn.with_shell(app_class:lower())
    end

    return found
end

--------------------------------------------------------------------------------
-- Widget Creation
--------------------------------------------------------------------------------

--- Create a single notification widget for the list
local function create_notification_widget(entry, index)
    -- Close button
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
            remove_from_history(index)
            if #notifications.history == 0 then
                notifications.popup.visible = false
            else
                refresh_popup()
            end
        end,
        id = "close_button"
    })

    close_button:connect_signal("mouse::enter", function()
        close_button_hovered = true
    end)
    close_button:connect_signal("mouse::leave", function()
        close_button_hovered = false
    end)

    local close_container = wibox.widget {
        {
            close_button,
            left = dpi(17),
            top = dpi(10),
            widget = wibox.container.margin
        },
        halign = "left",
        valign = "center",
        visible = false,
        widget = wibox.container.place
    }

    -- App class label
    local app_class_widget = wibox.widget {
        text = entry.app_class or "",
        font = font_with_size(theme.notification_font_size - 2),
        halign = "right",
        valign = "top",
        widget = wibox.widget.textbox
    }

    -- Content layout
    local content = wibox.widget {
        -- Icon
        {
            {
                image = entry.icon,
                resize = true,
                forced_width = config.notifications.icon_size,
                forced_height = config.notifications.icon_size,
                widget = wibox.widget.imagebox,
            },
            valign = "center",
            widget = wibox.container.place
        },
        -- Text content
        {
            -- Title row
            {
                nil,
                {
                    markup = "<b>" .. gears.string.xml_escape(entry.title) .. "</b>",
                    font = font_with_size(theme.notification_font_size - 1),
                    align = "left",
                    forced_height = dpi(theme.notification_font_size * 1.75),
                    widget = wibox.widget.textbox,
                },
                app_class_widget,
                expand = "inside",
                layout = wibox.layout.align.horizontal
            },
            -- Message row
            {
                nil,
                {
                    text = entry.text,
                    font = theme.notification_font,
                    align = "left",
                    forced_height = dpi(theme.notification_font_size * 1.75),
                    widget = wibox.widget.textbox,
                },
                {
                    text = format_timestamp(entry.timestamp),
                    font = font_with_size(theme.notification_font_size - 2),
                    widget = wibox.widget.textbox
                },
                expand = "inside",
                layout = wibox.layout.align.horizontal
            },
            spacing = dpi(2),
            layout = wibox.layout.fixed.vertical,
            forced_width = config.notifications.max_width
        },
        spacing = dpi(10),
        layout = wibox.layout.fixed.horizontal
    }

    -- Background container
    local bg_container = wibox.widget {
        {
            {
                content,
                margins = dpi(8),
                widget = wibox.container.margin
            },
            fg = theme.notifications.button_fg,
            bg = theme.notifications.notif_bg,
            shape = function(cr, width, height)
                gears.shape.rounded_rect(cr, width, height, dpi(6))
            end,
            shape_border_width = dpi(1),
            shape_border_color = theme.notifications.notif_border,
            widget = wibox.container.background,
            id = "notif_background"
        },
        top = dpi(10),
        bottom = 0,
        left = dpi(10),
        right = dpi(10),
        widget = wibox.container.margin
    }

    -- Stack layout for overlay
    local widget = wibox.widget {
        bg_container,
        close_container,
        layout = wibox.layout.stack
    }

    -- Click handlers
    widget:buttons(gears.table.join(
        awful.button({}, 1, function()
            if not close_button_hovered then
                jump_to_app(entry)
                notifications.popup.visible = false
            end
        end),
        awful.button({}, 3, function()
            remove_from_history(index)
            if #notifications.history == 0 then
                notifications.popup.visible = false
            else
                refresh_popup()
            end
        end)
    ))

    add_hover_cursor(widget)

    -- Hover effects
    widget:connect_signal("mouse::enter", function()
        close_container.visible = true
        local background = bg_container:get_children_by_id("notif_background")[1]
        if background then
            background.bg = theme.notifications.notif_bg_hover
            background.shape_border_color = theme.notifications.notif_border_hover
        end
    end)

    widget:connect_signal("mouse::leave", function()
        close_container.visible = false
        local background = bg_container:get_children_by_id("notif_background")[1]
        if background then
            background.bg = theme.notifications.notif_bg
            background.shape_border_color = theme.notifications.notif_border
        end
    end)

    return widget, entry
end

--- Create the preview panel widget
local function create_preview_panel()
    local preview_content = wibox.widget {
        id = "preview_content",
        layout = wibox.layout.fixed.vertical,
    }

    local preview_area = wibox.widget {
        {
            -- Separator
            {
                {
                    wibox.widget.base.make_widget(),
                    forced_width = dpi(1),
                    bg = theme.notifications.notif_border,
                    widget = wibox.container.background
                },
                top = dpi(15),
                bottom = dpi(15),
                widget = wibox.container.margin
            },
            -- Content
            {
                preview_content,
                halign = "center",
                valign = "center",
                widget = wibox.container.place
            },
            spacing = dpi(10),
            layout = wibox.layout.fixed.horizontal
        },
        strategy = "max",
        visible = false,
        widget = wibox.container.constraint
    }

    local preview_container = wibox.widget {
        {
            nil,
            preview_area,
            nil,
            expand = "inside",
            layout = wibox.layout.align.vertical
        },
        forced_width = config.notifications.max_width,
        visible = false,
        widget = wibox.container.constraint
    }

    return {
        area = preview_area,
        container = preview_container,
        content = preview_content,

        show = function(self, entry)
            if not entry then return end

            local content_widget = wibox.widget {
                -- Header
                {
                    {
                        {
                            image = entry.icon,
                            resize = true,
                            forced_width = dpi(48),
                            forced_height = dpi(48),
                            widget = wibox.widget.imagebox,
                        },
                        valign = "center",
                        widget = wibox.container.place
                    },
                    {
                        markup = "<b>" .. gears.string.xml_escape(entry.title or "") .. "</b>",
                        align = "left",
                        widget = wibox.widget.textbox
                    },
                    spacing = dpi(10),
                    layout = wibox.layout.fixed.horizontal
                },
                -- Full text
                {
                    text = entry.text,
                    align = "left",
                    wrap = "word",
                    widget = wibox.widget.textbox
                },
                spacing = dpi(8),
                layout = wibox.layout.fixed.vertical
            }

            self.content:reset()
            self.content:add(content_widget)
            self.area.visible = true
            self.container.visible = true
            notifications.current_preview = entry
        end,

        hide = function(self)
            self.content:reset()
            self.area.visible = false
            self.container.visible = false
            notifications.current_preview = nil
        end,
    }
end

--- Create the notification list widget
function notifications.create_list()
    local list_layout = wibox.layout.fixed.vertical()
    list_layout.spacing = 0

    -- Calculate visible items
    scroll_state.items_per_page = math.floor(
        (config.notifications.max_height - dpi(20)) / config.notifications.entry_height
    )

    local preview_panel = create_preview_panel()

    -- Create notification widgets
    local end_idx = math.min(
        scroll_state.start_idx + scroll_state.items_per_page - 1,
        #notifications.history
    )

    for i = scroll_state.start_idx, end_idx do
        local entry = notifications.history[i]
        local widget = create_notification_widget(entry, i)
        
        -- Preview on hover
        widget:connect_signal("mouse::enter", function()
            preview_panel:show(entry)
        end)
        widget:connect_signal("mouse::leave", function()
            preview_panel:hide()
        end)
        
        list_layout:add(widget)
    end

    -- Clear all button
    local clear_all_button = create_image_button({
        image_path = config_dir .. "theme-icons/clear.png",
        text_size = 11,
        image_size = dpi(20),
        padding = dpi(6),
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
            notifications.current_preview = nil
            update_count()
            save_history()
            notifications.popup.visible = false
        end
    })

    -- Empty state
    local no_notifications = wibox.widget {
        {
            text = "No notifications",
            font = font_with_size(theme.notification_font_size - 1),
            halign = "center",
            widget = wibox.widget.textbox
        },
        margins = dpi(5),
        widget = wibox.container.margin
    }

    -- Header body
    local header_body = #notifications.history > 0 and wibox.widget
    {
        clear_all_button,
        {
            text = "Notifications",
            align = "center",
            widget = wibox.widget.textbox
        },
        spacing = -dpi(32),
        fill_space = true,
        layout = wibox.layout.fixed.horizontal
    }
    or no_notifications

    -- Header with clear button or empty state
    local header = wibox.widget {
        header_body,
        top = dpi(10),
        left = dpi(10),
        right = dpi(10),
        widget = wibox.container.margin
    }

    -- List widget with footer
    local list_widget = wibox.widget
    {
        {
            header,
            list_layout,
            layout = wibox.layout.fixed.vertical,
            spacing = dpi(5)
        },
        bottom = dpi(10),
        widget = wibox.container.margin
    }

    -- Main horizontal layout
    local main_layout = wibox.layout.fixed.horizontal()
    main_layout.spacing = 0

    -- Add list
    main_layout:add(wibox.widget {
        list_widget,
        forced_width = #notifications.history > 0
            and config.notifications.max_width + dpi(10)
            or nil,
        widget = wibox.container.constraint
    })

    -- Add preview panel
    main_layout:add(preview_panel.container)

    -- Scroll handlers
    main_layout:buttons(gears.table.join(
        awful.button({}, 4, function()  -- Scroll up
            if scroll_state.start_idx > 1 then
                scroll_state.start_idx = math.max(1, scroll_state.start_idx - 1)
                refresh_popup()
            end
        end),
        awful.button({}, 5, function()  -- Scroll down
            local max_start = math.max(1, #notifications.history - scroll_state.items_per_page + 1)
            if scroll_state.start_idx < max_start then
                scroll_state.start_idx = math.min(max_start, scroll_state.start_idx + 1)
                refresh_popup()
            end
        end)
    ))

    return main_layout
end

--------------------------------------------------------------------------------
-- Main Button and Popup
--------------------------------------------------------------------------------

--- Test if popup should close (not hovered)
local function test_not_hovered()
    gears.timer.start_new(0.1, function()
        if not notifications.hovered and notifications.popup then
            notifications.popup.visible = false
        end
        return false
    end)
end

--- Create the notification button and popup
function notifications.create_button()
    -- Load saved history
    load_history()

    local button = create_labeled_image_button({
        image_path = beautiful.notification_icon or config_dir .. "theme-icons/notification.png",
        image_size = config.notifications.button_size,
        label_text = tostring(#notifications.history),
        text_size = 12,
        padding = dpi(3),
        opacity = 0.5,
        opacity_hover = 1,
        fg_color = theme.notifications.button_fg,
        hover_fg = theme.notifications.button_fg_focus,
        bg_color = theme.notifications.button_bg,
        border_color = theme.notifications.button_border,
        hover_bg = theme.notifications.button_bg_focus,
        hover_border = theme.notifications.button_border_focus,
        shape_radius = dpi(4),
        on_click = function()
            if not notifications.popup.visible then
                scroll_state.start_idx = 1
                notifications.popup.widget = notifications.create_list()
            end
            notifications.popup.screen = mouse.screen
            notifications.popup.visible = not notifications.popup.visible
        end,
        id = "notification_button"
    })

    notifications.button = button

    -- Hover handling for button
    button:connect_signal("mouse::enter", function()
        notifications.hovered = true
    end)
    button:connect_signal("mouse::leave", function()
        notifications.hovered = false
        test_not_hovered()
    end)

    -- Create popup
    notifications.popup = awful.popup {
        widget = notifications.create_list(),
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

    -- Hover handling for popup
    notifications.popup:connect_signal("mouse::enter", function()
        notifications.hovered = true
    end)
    notifications.popup:connect_signal("mouse::leave", function()
        notifications.hovered = false
        test_not_hovered()
    end)

    return wibox.widget {
        button,
        margins = dpi(4),
        widget = wibox.container.margin
    }
end

--------------------------------------------------------------------------------
-- Notification Signal Handlers
--------------------------------------------------------------------------------

-- Handle new notifications - store data and let notification display normally
naughty.connect_signal("added", function(n)
    add_to_history(n)
end)

-- Custom display handler (optional title formatting)
naughty.connect_signal("request::display", function(n)
    local function format_title(title)
        return string.format('<span font="%s"><b>%s</b></span>', beautiful.font, title)
    end
    
    -- Format title
    n.title = format_title(n.title)

    -- Create notification box with default template
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
                                layout = wibox.layout.fixed.vertical,
                            },
                            fill_space = true,
                            spacing = dpi(18),
                            layout = wibox.layout.fixed.horizontal,
                        },
                        spacing = dpi(10),
                        layout = wibox.layout.fixed.vertical,
                    },
                    margins = beautiful.notification_margin,
                    widget = wibox.container.margin,
                },
                id = "background_role",
                widget = naughty.container.background,
            },
            strategy = "max",
            width = beautiful.notification_max_width,
            widget = wibox.container.constraint,
        }
    }

    -- Store reference to client info for jump-to functionality
    local app_class = ""
    local app_name = ""
    if n.clients and #n.clients > 0 then
        app_class = n.clients[1].class or ""
        app_name = n.clients[1].name or ""
    elseif n.app_name then
        app_name = n.app_name
    end

    -- Click handlers
    if box then
        box.buttons = gears.table.join(
            -- Left-click: jump to app and dismiss
            awful.button({}, 1, function()
                -- Find matching entry to get stored app info
                local entry = {app_class = app_class, app_name = app_name}
                jump_to_app(entry)
                n:destroy(naughty.notification_closed_reason.dismissed_by_user)
            end),
            -- Right-click: just dismiss
            awful.button({}, 3, function()
                n:destroy(naughty.notification_closed_reason.expired)
            end)
        )
    end
end)

return notifications