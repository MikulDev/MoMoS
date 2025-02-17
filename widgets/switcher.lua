local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local beautiful = require("beautiful")
local dpi = require("beautiful.xresources").apply_dpi
local naughty = require("naughty")
local util = require("util")

-- Global state table
switcher_data = {
    popup = nil,
    tasks = {},
    sel_task = 0,
    grabber = nil,
    is_open = false,
    desktop_entries = {}, -- Store desktop entries for icon lookup
    current_label = nil   -- Reference to the label widget
}

local switcher = {}

local function set_title(text)
    switcher_data.current_label.markup = '<span font="11" color="#ffffff">' ..(text or "Unknown") .. '</span>'
end

-- Create a custom task widget
local function create_task_widget(c)
    local widget = wibox.widget {
        {
            {
                -- Icon widget will be replaced with actual icon
                id = "icon",
                resize = true,
                forced_width = dpi(32),
                forced_height = dpi(32),
                widget = wibox.widget.imagebox
            },
            margins = dpi(12),
            widget = wibox.container.margin
        },
        id = "background",
        bg = beautiful.tasklist_bg_normal,
        shape = gears.shape.rounded_rect,
        shape_border_width = dpi(1),
        shape_border_color = beautiful.tasklist_shape_border_color,
        forced_width = dpi(64),
        forced_height = dpi(64),
        widget = wibox.container.background
    }

    -- Find icon for the application
    local function find_client_icon()
        -- First try to get icon directly from client
        if c.icon then
            return gears.surface.load(c.icon)
        end

        -- Try to find icon from .desktop files
        local client_class = string.lower(c.class or "")
        for _, entry in ipairs(switcher_data.desktop_entries) do
            local entry_name = string.lower(entry.name)
            if entry_name:match(client_class) or client_class:match(entry_name) then
                if entry.icon then
                    return entry.icon
                end
            end
        end

        -- Fallback to default icon
        return beautiful.awesome_icon
    end

    -- Set the icon
    local icon = widget:get_children_by_id("icon")[1]
    icon.image = find_client_icon()

    -- Handle hover effects
    local bg = widget:get_children_by_id("background")[1]

    widget:connect_signal("mouse::enter", function()
        for _, task in ipairs(switcher_data.tasks) do
            task.widget:emit_signal("mouse::leave")
        end
        bg.bg = beautiful.tasklist_bg_focus
        bg.shape_border_color = beautiful.tasklist_shape_border_color_focus
        -- Update the label text
        if switcher_data.current_label then
            set_title(c.name)
        end
    end)

    widget:connect_signal("mouse::leave", function()
        bg.bg = c.minimized and beautiful.tasklist_bg_minimize or beautiful.tasklist_bg_normal
        bg.shape_border_color = beautiful.tasklist_shape_border_color
    end)

    -- Handle click events
    widget:buttons(gears.table.join(
    awful.button({}, 1, function()
        jump_to_client(c)
        client.focus = c
        c:raise()
        close_popup()
    end)
))

return widget
end

function close_popup()
    if switcher_data.popup then
        switcher_data.popup.visible = false
        switcher_data.is_open = false
        if switcher_data.grabber then
            awful.keygrabber.stop(switcher_data.grabber)
        end
    end
end

function switcher.show()
    if switcher_data.is_open then
        return
    end

    -- Scan desktop files for icons if not already done
    if #switcher_data.desktop_entries == 0 then
        scan_desktop_files()
    end

    -- Unfocus all clients when box opens
    client.focus = nil

    switcher_data.is_open = true
    switcher_data.tasks = {}
    switcher_data.sel_task = 0

    -- Create grid layout for tasks
    local task_grid = wibox.layout.grid()
    local client_count = #client.get()
    local width_clients = client_count <= 4 and client_count or math.ceil(client_count / 2)
    task_grid.forced_num_cols = width_clients
    task_grid.spacing = dpi(12)
    if client_count < 3 then
        task_grid.forced_width = dpi(72)
    end

    -- Add all clients to the grid
    for _, c in ipairs(client.get()) do
        local task_widget = create_task_widget(c)
        task_grid:add(task_widget)
        table.insert(switcher_data.tasks, {widget = task_widget, client = c})
    end

    -- Create the window title label
    local title_label = wibox.widget {
        markup = '<span font="11" color="#ffffff"></span>',
        align = "center",
        forced_width = width_clients * dpi(36),
        widget = wibox.widget.textbox
    }
    switcher_data.current_label = title_label

    -- Create main layout with grid and label
    local main_layout = wibox.layout.fixed.vertical()
    main_layout.spacing = dpi(12)
    main_layout:add(task_grid)
    main_layout:add(title_label)

    -- Create the popup
    switcher_data.popup = awful.popup {
        widget = wibox.widget {
            main_layout,
            margins = dpi(12),
            widget = wibox.container.margin,
        },
        screen = mouse.screen,
        bg = '#0f0f0fa0',
        border_color = '#252525a0',
        border_width = dpi(1),
        ontop = true,
        placement = awful.placement.centered,
        shape = gears.shape.rounded_rect,
        visible = false
    }
    gears.timer.start_new(0.01, function()
        switcher_data.popup.visible = true
    end)

    -- Handle keyboard navigation
    switcher_data.grabber = awful.keygrabber.run(function(mod, key, event)
        if event == "press" then
            if key == "Escape" then
                close_popup()
                set_focus_to_mouse()
                return
            elseif key == "Tab" then
                -- Un-highlight current task
                if switcher_data.sel_task > 0 then
                    switcher_data.tasks[switcher_data.sel_task].widget:emit_signal("mouse::leave")
                end

                -- Select next task
                switcher_data.sel_task = (switcher_data.sel_task % #switcher_data.tasks) + 1

                -- Highlight new selection and update label
                local sel = switcher_data.tasks[switcher_data.sel_task]
                sel.widget:emit_signal("mouse::enter")
                set_title(sel.client.name)
            elseif key == "Return" then
                local sel = switcher_data.tasks[switcher_data.sel_task]
                if sel then
                    jump_to_client(sel.client)
                    client.focus = sel.client
                    sel.client:raise()
                end
                close_popup()
            end
            -- Passthrough other keybindings
            execute_keybind(key, mod)
        end
    end)

    gears.timer.start_new(0.01, function()
        if #switcher_data.tasks > 0 then
            switcher_data.sel_task = 1
            local first_task = switcher_data.tasks[switcher_data.sel_task]
            first_task.widget:emit_signal("mouse::enter")
            local title = is_string_empty(first_task.client.name)
                          and first_task.client.class
                          or first_task.client.name
            set_title(title)
        end
    end)

    -- Close when clicked outside
    client.connect_signal("button::press", close_popup)
    switcher_data.popup:connect_signal("button::press", close_popup)
end

function set_default_title()
    if #switcher_data.tasks > 0 then
        switcher_data.sel_task = 1
        local first_task = switcher_data.tasks[switcher_data.sel_task]
        set_title(first_task.client.name)
    end
end

client.connect_signal("list", function(c)
    local switcher_enabled = switcher_data.is_open
    close_popup()
    if switcher_enabled then
        switcher.show()
    end
end)

return switcher