local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local wibox = require("wibox")
local naughty = require("naughty")
local dpi = require("beautiful.xresources").apply_dpi
local util = require("util")

local config_dir = gears.filesystem.get_configuration_dir()
local icon_dir = config_dir .. "theme-icons/"

local theme = load_util("theme")

local calendar_icons = {
    left_arrow = icon_dir .. "left_arrow.png",
    right_arrow = icon_dir .. "right_arrow.png"
}

-- Create weekday headers
local weekdays = {"Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"}
local weekday_widgets = {}
for _, day in ipairs(weekdays) do
    local weekday = wibox.widget {
        {
            markup = string.format(
                '<span font="%s" color="%s">%s</span>',
                font_with_size(dpi(12)),
                theme.fg_focus .. "aa",
                day
            ),
            align = 'center',
            valign = 'center',
            widget = wibox.widget.textbox
        },
        margins = dpi(8),
        widget = wibox.container.margin
    }
    table.insert(weekday_widgets, weekday)
end

-- Calendar helper functions
local function get_days_in_month(month, year)
    local days_in_month = {31,28,31,30,31,30,31,31,30,31,30,31}
    if month == 2 then
        if year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0) then
            return 29
        end
    end
    return days_in_month[month]
end

local function get_first_day_of_month(month, year)
    return os.date("*t", os.time({year=year, month=month, day=1})).wday
end

-- Create a day cell widget
local function create_day_widget(text, is_current_day)
    if text == "" then
        return nil -- Return nil for empty cells
    end

    local bg_color = is_current_day and theme.calendar.date_bg_current or theme.calendar.date_bg
    local fg_color = is_current_day and theme.calendar.date_fg_current or theme.calendar.date_fg
    local border_color = is_current_day and 
        (theme.calendar.date_border_current .. "50") or 
        (theme.calendar.date_border .. "50")

    local day_widget = wibox.widget {
        {
            {
                text = text,
                font = theme.font,
                align = 'center',
                valign = 'center',
                widget = wibox.widget.textbox
            },
            top = dpi(8),
            bottom = dpi(8),
            left = dpi(12),
            right = dpi(12),
            widget = wibox.container.margin
        },
        bg = bg_color,
        fg = fg_color,
        shape = function(cr, width, height)
            gears.shape.rectangle(cr, width, height)
        end,
        shape_border_width = dpi(1),
        shape_border_color = border_color,
        widget = wibox.container.background
    }

    -- Add hover effect
    day_widget:connect_signal("mouse::enter", function()
        if not is_current_day then
            day_widget.bg = theme.calendar.date_bg_hover
            day_widget.border_color = theme.calendar.date_border_hover .. "50"
            day_widget.fg = theme.calendar.date_fg_hover
        end
    end)
    day_widget:connect_signal("mouse::leave", function()
        if not is_current_day then
            day_widget.bg = theme.calendar.date_bg
            day_widget.border_color = theme.calendar.date_border .. "50"
            day_widget.fg = theme.calendar.date_fg
        end
    end)

    return day_widget
end

-- Create custom calendar widget
local calendar = {
    hovered = false
}

-- Functions to change months
function calendar.next_month()
    local month = calendar.current_date.month + 1
    local year = calendar.current_date.year

    if month > 12 then
        month = 1
        year = year + 1
    end

    calendar.current_date = {
        year = year,
        month = month,
        day = 1  -- Reset to first day of month
    }

    calendar.update_header()
    calendar.update_grid()
end

function calendar.prev_month()
    local month = calendar.current_date.month - 1
    local year = calendar.current_date.year

    if month < 1 then
        month = 12
        year = year - 1
    end

    calendar.current_date = {
        year = year,
        month = month,
        day = 1  -- Reset to first day of month
    }

    calendar.update_header()
    calendar.update_grid()
end

-- Create month/year header
function calendar.update_header()
    local month_names = {"January", "February", "March", "April", "May", "June",
                       "July", "August", "September", "October", "November", "December"}

    local text = string.format(
        '<span font="%s %s" color="%s">%s %d</span>',
        theme.font,
        13,
        theme.fg_focus,
        month_names[calendar.current_date.month],
        calendar.current_date.year
    )

    -- Update the text in the middle widget
    local month_text = calendar.header_widget:get_children_by_id("month_text")[1]
    month_text.markup = text
end

-- Update calendar grid
function calendar.update_grid()
    local current_date = os.date("*t")
    local days_in_month = get_days_in_month(calendar.current_date.month, calendar.current_date.year)
    local first_day = get_first_day_of_month(calendar.current_date.month, calendar.current_date.year)
    -- Remove this line that was causing the offset:
    -- first_day = first_day == 1 and 7 or first_day - 1

    -- Calculate number of rows needed
    local num_rows = math.ceil((days_in_month + first_day - 1) / 7)

    -- Clear existing widgets
    calendar.days_grid:reset()

    -- Add weekday headers
    for i, widget in ipairs(weekday_widgets) do
    calendar.days_grid:add(widget)
    end

    -- Add days of the month
    local day_number = 1

    -- Fill in empty cells before the first day
    for i = 1, first_day - 1 do
    calendar.days_grid:add(wibox.widget.base.empty_widget())
    end

    -- Get real current date for highlighting
    local real_current_date = os.date("*t")
    local is_current_month = real_current_date.month == calendar.current_date.month
    and real_current_date.year == calendar.current_date.year

    -- Then add the days of the month
    for day = 1, days_in_month do
    local is_current_day = is_current_month and day == real_current_date.day
    calendar.days_grid:add(create_day_widget(day, is_current_day))
    end

    -- Fill remaining cells to complete the grid
    local total_cells = (num_rows + 1) * 7  -- +1 for header row
    local remaining = total_cells - (days_in_month + first_day - 1) - 7  -- -7 for header row
    for i = 1, remaining do
    calendar.days_grid:add(wibox.widget.base.empty_widget())
    end
end

function calendar.toggle()
    if calendar.popup.visible then
        calendar.popup.visible = false
    else
        -- Update calendar data
        calendar.current_date = os.date("*t")
        calendar.update_header()
        calendar.update_grid()
        -- Render the calendar for proper sizing
        calendar.popup.visible = true
        calendar.popup.visible = false

        -- Position after a slight delay to ensure rendering
        gears.timer.start_new(0.01, function()
            -- Calculate position relative to the screen's geometry
            local widget_screen = mouse.screen
            if not widget_screen then return false end

            calendar.popup.x = widget_screen.geometry.x + widget_screen.geometry.width - calendar.popup.width - dpi(10)
            calendar.popup.y = widget_screen.geometry.y + beautiful.wibar_height + dpi(10)
            calendar.popup.visible = true
            return false
        end)
    end
end

function calendar_init()

    -- Store current date
    calendar.current_date = os.date("*t")

	-- Create navigation buttons
    local prev_button = create_image_button({
	    image_path = calendar_icons.left_arrow,
	    image_size = dpi(12),
	    padding = dpi(10),
	    opacity = 0.5,
	    opacity_hover = 1,
	    bg_color = theme.calendar.button_bg,
	    border_color = theme.calendar.button_border,
	    hover_bg = theme.calendar.button_bg_focus,
	    hover_border = theme.calendar.button_border_focus,
	    shape_radius = dpi(6),
	    on_click = function() 
	        calendar.prev_month()
	    end
	})
	
	local next_button = create_image_button({
	    image_path = calendar_icons.right_arrow,
	    image_size = dpi(12),
	    padding = dpi(10),
	    opacity = 0.5,
	    opacity_hover = 1,
	    bg_color = theme.calendar.button_bg,
	    border_color = theme.calendar.button_border,
	    hover_bg = theme.calendar.button_bg_focus,
	    hover_border = theme.calendar.button_border_focus,
	    shape_radius = dpi(6),
	    on_click = function() 
	        calendar.next_month()
	    end
	})

	-- Create header widget with navigation buttons
    calendar.header_widget = wibox.widget {
        {
            prev_button,
            {
                id = "month_text",
                markup = "",
                align = 'center',
                valign = 'center',
                widget = wibox.widget.textbox
            },
            next_button,
            layout = wibox.layout.align.horizontal
        },
        widget = wibox.container.background
    }

    -- Create grid for days
    calendar.days_grid = wibox.widget {
        spacing = dpi(4),
        forced_num_cols = 7,
        layout = wibox.layout.grid
    }

    -- Create the final layout
    calendar.widget = wibox.widget {
        {
            {
                calendar.header_widget,
                margins = dpi(10),
                widget = wibox.container.margin
            },
            {
                calendar.days_grid,
                margins = dpi(10),
                widget = wibox.container.margin
            },
            layout = wibox.layout.fixed.vertical
        },
        widget = wibox.container.background
    }

    -- Create the popup window
    calendar.popup = awful.popup {
        ontop = true,
        visible = false,
        shape = function(cr, width, height)
            gears.shape.rounded_rect(cr, width, height, dpi(16))
        end,
        border_width = dpi(1),
        border_color = theme.calendar.border,
        bg = theme.calendar.bg,
        widget = {
            calendar.widget,
            margins = dpi(2),
            widget = wibox.container.margin
        }
    }

    calendar.popup:connect_signal("mouse::enter", function()
        calendar.hovered = true
    end)

    calendar.popup:connect_signal("mouse::leave", function()
        calendar.hovered = false
        gears.timer.start_new(0.1, function()
            if not calendar.hovered then
                calendar.popup.visible = false
            end
            return false
        end)
    end)

    -- Update everything
    calendar.update_header()
    calendar.update_grid()

    return calendar
end

function calendar.attach(widget)
    widget:connect_signal("mouse::enter", function()
        calendar.hovered = true
    end)

    widget:connect_signal("mouse::leave", function()
        calendar.hovered = false
        gears.timer.start_new(0.1, function()
            if not calendar.hovered then
                calendar.popup.visible = false
            end
            return false
        end)
    end)
end

return calendar