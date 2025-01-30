local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local beautiful = require("beautiful")
local dpi = require("beautiful.xresources").apply_dpi

-- Global state table
switcher_data = {
    popup = nil,
    tasks = {},
    sel_task = 0,
    grabber = nil,
    is_open = false
}

local switcher = {}

local function close_popup()
    if switcher_data.popup then
        switcher_data.popup.visible = false
        switcher_data.is_open = false
        if switcher_data.grabber then
            awful.keygrabber.stop(switcher_data.grabber)
        end
    end
end

local function set_focus_to_mouse()
    -- Get all clients in the current tag
    local clients = client.get()
    local focused = false
    local coords = mouse.coords()
    
    -- Find topmost client under cursor
    for _, c in ipairs(clients) do
        if c:geometry().x < coords.x and
           c:geometry().y < coords.y and
           c:geometry().x + c:geometry().width > coords.x and
           c:geometry().y + c:geometry().height > coords.y and
           c:isvisible() then
            client.focus = c
            focused = true
            break
        end
    end
    
    -- If no client was found under cursor, remove focus
    if not focused then
        client.focus = nil
    end
end

function switcher.show()
    if switcher_data.is_open then
        return
    end
    
    switcher_data.is_open = true
    switcher_data.tasks = {}
    switcher_data.sel_task = 0
    
    local task_switcher = wibox.widget {
        {
            id = 'task_list',
            widget = awful.widget.tasklist {
                screen = screen[1],
                filter = awful.widget.tasklist.filter.allscreen,
                buttons = tasklist_buttons,
                style = {
                    shape = gears.shape.rounded_rect,
                    spacing = 12,
                },
                layout = {
                    -- Force 2 rows from left to right
                    forced_num_cols = #client.get() / 2,
                    layout = wibox.layout.grid.vertical
                },
                widget_template = {
                    {
                        {
                            id = 'clienticon',
                            widget = awful.widget.clienticon,
                        },
                        margins = 12,
                        widget = wibox.container.margin,
                    },
                    id = 'background_role',
                    forced_width = dpi(64),
                    forced_height = dpi(64),
                    widget = wibox.container.background,
                    create_callback = function(self, c, index, objects)
                        self:get_children_by_id('clienticon')[1].client = c
                        local bg = self:get_children_by_id('background_role')[1]

                        -- Highlighting icons when hovered
                        self:connect_signal("mouse::enter", function()
                            bg.bg = beautiful.tasklist_bg_focus
                            bg.shape_border_color = beautiful.tasklist_shape_border_color_focus
                        end)
                        
                        -- Remove highlighting when un-hovered
                        self:connect_signal("mouse::leave", function()
                            if (c ~= client.focus) then
                                if (c.minimized) then
                                    bg.bg = beautiful.tasklist_bg_minimize
                                else
                                    bg.bg = beautiful.tasklist_bg_normal
                                end
                                bg.shape_border_color = beautiful.tasklist_shape_border_color
                            end
                        end)

                        -- Add to the list of tasks
                        table.insert(switcher_data.tasks, {self, c})
                    end,
                },
            }
        },
        margins = 12,
        widget = wibox.container.margin,
    }

    switcher_data.popup = awful.popup {
        widget = task_switcher,
        screen = mouse.screen,
        bg = '#0f0f0fa0',
        border_color = '#252525a0',
        border_width = 1,
        ontop = true,
        placement = awful.placement.centered,
        shape = gears.shape.rounded_rect,
    }

    switcher_data.grabber = awful.keygrabber.run(function(mod, key, event)
        if (event == "press") then
            -- Close popup
            if (key == "Escape") then
                close_popup()
                set_focus_to_mouse()
                return
            -- Cycle through tasks
            elseif (key == "Tab") then
                count = 0
                for _, c in ipairs(switcher_data.tasks) do
                    count = count + 1
                    -- Un-highlight all tasks
                    c[1]:emit_signal("mouse::leave")
                end
                -- Highlight and store index of next task
                switcher_data.sel_task = (switcher_data.sel_task % count) + 1
                switcher_data.tasks[switcher_data.sel_task][1]:emit_signal("mouse::enter")
            -- Open selected task
            elseif (key == "Return") then
                local sel_client = switcher_data.tasks[switcher_data.sel_task][2]
                client.focus = sel_client
                sel_client.first_tag:view_only()
                close_popup()
            end
        end
    end)

    -- Close when clicked outside box
    client.connect_signal("button::press", close_popup)
    switcher_data.popup:connect_signal("button::press", close_popup)

    -- Unfocus all clients when box opens
    client.focus = nil
end

return switcher