local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local wibox = require("wibox")
local dpi = require("beautiful.xresources").apply_dpi

local config_dir = gears.filesystem.get_configuration_dir()
local theme = dofile(config_dir .. "theme.lua")

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
            margins = dpi(8),
            widget = wibox.container.margin
        },
        bg = bg_color,
        fg = fg_color,
        shape = function(cr, width, height)
            gears.shape.rectangle(cr, width, height)
        end,
        shape_border_width = 1,
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
local calendar = {}

function calendar.new()
    local cal = {}
    
    -- Create month/year header
    function cal:update_header()
        local current_date = os.date("*t")
        local month_names = {"January", "February", "March", "April", "May", "June",
                           "July", "August", "September", "October", "November", "December"}
        
        self.header_widget.markup = string.format(
            '<span font="%s %s" color="%s">%s %d</span>',
            theme.font,
            dpi(13),
            theme.fg_focus,
            month_names[current_date.month],
            current_date.year
        )
    end

    -- Create header widget
    cal.header_widget = wibox.widget {
        markup = "",
        align = 'center',
        valign = 'center',
        widget = wibox.widget.textbox
    }

    -- Create weekday headers
    local weekdays = {"Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"}
    local weekday_widgets = {}
    for _, day in ipairs(weekdays) do
        local weekday = wibox.widget {
            {
                markup = string.format(
                    '<span font="%s" color="%s">%s</span>',
                    theme.font,
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

    -- Create grid for days
    cal.days_grid = wibox.widget {
        spacing = dpi(4),
        forced_num_cols = 7,
        layout = wibox.layout.grid
    }

    -- Update calendar grid
    function cal:update_grid()
        local current_date = os.date("*t")
        local days_in_month = get_days_in_month(current_date.month, current_date.year)
        local first_day = get_first_day_of_month(current_date.month, current_date.year)
        first_day = first_day == 1 and 7 or first_day - 1

        -- Calculate number of rows needed
        local num_rows = math.ceil((days_in_month + first_day - 1) / 7)

        -- Clear existing widgets
        cal.days_grid:reset()

        -- Add weekday headers
        for i, widget in ipairs(weekday_widgets) do
            cal.days_grid:add(widget)
        end

        -- Add days of the month
        local day_number = 1
        
        -- First, fill in empty cells before the first day
        for i = 1, first_day - 1 do
            cal.days_grid:add(wibox.widget.base.empty_widget())
        end
        
        -- Then add the days of the month
        for day = 1, days_in_month do
            local is_current_day = day == current_date.day
            cal.days_grid:add(create_day_widget(day, is_current_day))
        end
        
        -- Fill remaining cells to complete the grid
        local total_cells = (num_rows + 1) * 7  -- +1 for header row
        local remaining = total_cells - (days_in_month + first_day - 1) - 7  -- -7 for header row
        for i = 1, remaining do
            cal.days_grid:add(wibox.widget.base.empty_widget())
        end
    end

    -- Create the final layout
    cal.widget = wibox.widget {
        {
            {
                cal.header_widget,
                margins = dpi(10),
                widget = wibox.container.margin
            },
            {
                cal.days_grid,
                margins = dpi(10),
                widget = wibox.container.margin
            },
            layout = wibox.layout.fixed.vertical
        },
        widget = wibox.container.background
    }

    -- Create the popup window
    cal.popup = awful.popup {
        ontop = true,
        visible = false,
        shape = function(cr, width, height)
            gears.shape.rounded_rect(cr, width, height, dpi(16))
        end,
        border_width = 1,
        border_color = theme.calendar.border,
        bg = theme.calendar_bg,
        widget = {
            cal.widget,
            margins = dpi(2),
            widget = wibox.container.margin
        }
    }

    -- Update everything
    cal:update_header()
    cal:update_grid()

    -- Attach to a widget
    function cal:attach(widget)
        -- Pre-render the calendar once to get correct sizes
        cal:update_header()
        cal:update_grid()
        
        local function position_calendar()
            local s = awful.screen.focused()
            cal.popup.x = s.geometry.width - cal.popup.width - dpi(10)
            cal.popup.y = s.geometry.y + beautiful.wibar_height + dpi(10)
        end

        local hovered = false
        local function show_calendar()
            -- Update calendar when shown
            cal:update_header()
            cal:update_grid()
            
            -- Show calendar
            if not cal.popup.visible then
				cal.popup.visible = true
                -- Wait for calendar to fully init before positioning
                gears.timer.start_new(0.01, function()
                    position_calendar()
                    return false
                end)
            end
        end

        local function hide_calendar()
            if cal.popup.visible then
                cal.popup.visible = false
            end
        end

		local keygrabber = awful.keygrabber {
	        autostart = false,
	        keypressed_callback = function(_, mod, key)
	            if key == "Escape" then
					hide_calendar()
				end
	        end
	    }

        -- Connect signals
        widget:connect_signal("mouse::enter", show_calendar)
        widget:connect_signal("mouse::leave", function()
        	gears.timer.start_new(0.1, function()
				if not hovered then
					hide_calendar()   
				end         	
                return false
            end)
        end)
        cal.popup:connect_signal("mouse::enter", function() 
			keygrabber:start()
			hovered = true 
		end)
        cal.popup:connect_signal("mouse::leave", function() 
			keygrabber:stop()
			hovered = false 
			hide_calendar()
		end)
    end

    return cal
end

return calendar