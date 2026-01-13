--[[
    Navigable Item Widget for Awesome WM
    
    Creates widgets that integrate with BasePopup's navigation system.
    Provides consistent hover/focus styling and signal handling.
    
    Features:
    - Automatic focus/unfocus signal handling
    - Configurable styling for normal, hover, and focus states
    - Mouse hover synchronization with keyboard navigation
    - Click handlers
    
    Usage:
        local create_nav_item = require("navigable_item")
        
        local item = create_nav_item({
            content = my_widget,
            bg = "#1a1a1a",
            bg_focus = "#2a2a2a",
            on_select = function(data) ... end,
            data = { name = "Item 1" }
        })
        
        -- Register with popup
        popup:register_item(item.widget, item.data, item.on_select)
]]

local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local wibox = require("wibox")
local dpi = require("beautiful.xresources").apply_dpi

--------------------------------------------------------------------------------
-- Navigable Item Factory
--------------------------------------------------------------------------------

--- Create a navigable item widget
-- @param args Configuration table
-- @return table { widget, data, on_select }
local function create_navigable_item(args)
    args = args or {}
    
    -- Content widget (required)
    local content = args.content or wibox.widget {
        text = "Item",
        widget = wibox.widget.textbox,
    }
    
    -- Styling
    local bg_normal = args.bg or args.bg_normal or beautiful.bg_normal or "#1a1a1a"
    local bg_focus = args.bg_focus or args.bg_hover or beautiful.bg_focus or "#2a2a2a"
    local fg_normal = args.fg or args.fg_normal or beautiful.fg_normal or "#ffffff"
    local fg_focus = args.fg_focus or args.fg_hover or beautiful.fg_focus or "#ffffff"
    local border_normal = args.border_color or beautiful.border_normal or "#333333"
    local border_focus = args.border_color_focus or beautiful.border_focus or "#555555"
    local border_width = args.border_width or dpi(1)
    local shape_radius = args.shape_radius or dpi(8)
    local padding = args.padding or dpi(8)
    
    -- Data and callbacks
    local data = args.data
    local on_select = args.on_select
    local on_click = args.on_click or on_select
    local on_right_click = args.on_right_click
    
    -- Track focus state
    local is_focused = false
    
    -- Create the container widget
    local widget = wibox.widget {
        {
            content,
            margins = padding,
            widget = wibox.container.margin,
        },
        bg = bg_normal,
        fg = fg_normal,
        shape = function(cr, w, h)
            gears.shape.rounded_rect(cr, w, h, shape_radius)
        end,
        shape_border_width = border_width,
        shape_border_color = border_normal,
        widget = wibox.container.background,
    }
    
    -- Size constraints
    if args.width then widget.forced_width = args.width end
    if args.height then widget.forced_height = args.height end
    
    -- Style application helper
    local function apply_style(focused)
        is_focused = focused
        widget.bg = focused and bg_focus or bg_normal
        widget.fg = focused and fg_focus or fg_normal
        widget.shape_border_color = focused and border_focus or border_normal
    end
    
    -- Focus signals (from BasePopup navigation)
    widget:connect_signal("item::focus", function()
        apply_style(true)
    end)
    
    widget:connect_signal("item::unfocus", function()
        apply_style(false)
    end)
    
    -- Mouse hover (syncs with keyboard navigation via BasePopup)
    widget:connect_signal("mouse::enter", function()
        if not is_focused then
            apply_style(true)
        end
    end)
    
    widget:connect_signal("mouse::leave", function()
        if not is_focused then
            apply_style(false)
        end
    end)
    
    -- Click handlers
    local buttons = {}
    
    if on_click then
        table.insert(buttons, awful.button({}, 1, function()
            on_click(data)
        end))
    end
    
    if on_right_click then
        table.insert(buttons, awful.button({}, 3, function()
            on_right_click(data)
        end))
    end
    
    if #buttons > 0 then
        widget:buttons(gears.table.join(table.unpack(buttons)))
    end
    
    -- Add hover cursor if clickable
    if on_click and add_hover_cursor then
        add_hover_cursor(widget)
    end
    
    -- Return the item structure
    return {
        widget = widget,
        data = data,
        on_select = on_select,
        
        -- Utility methods
        set_content = function(self, new_content)
            local margin = widget:get_children()[1]
            if margin then
                margin:set_widget(new_content)
            end
        end,
        
        set_style = function(self, style)
            if style.bg then bg_normal = style.bg end
            if style.bg_focus then bg_focus = style.bg_focus end
            if style.fg then fg_normal = style.fg end
            if style.fg_focus then fg_focus = style.fg_focus end
            apply_style(is_focused)
        end,
        
        focus = function(self)
            apply_style(true)
        end,
        
        unfocus = function(self)
            apply_style(false)
        end,
    }
end

--------------------------------------------------------------------------------
-- Convenience Factories
--------------------------------------------------------------------------------

--- Create a simple text item
-- @param text The text to display
-- @param args Additional configuration
-- @return navigable item
local function create_text_item(text, args)
    args = args or {}
    args.content = wibox.widget {
        text = text,
        font = args.font or beautiful.font,
        widget = wibox.widget.textbox,
    }
    return create_navigable_item(args)
end

--- Create an icon + text item
-- @param args Configuration with icon_path, text, etc.
-- @return navigable item
local function create_icon_text_item(args)
    args = args or {}
    
    local icon_size = args.icon_size or dpi(24)
    local spacing = args.spacing or dpi(8)
    
    local content = wibox.widget {
        -- Icon
        {
            {
                image = args.icon_path,
                resize = true,
                forced_width = icon_size,
                forced_height = icon_size,
                widget = wibox.widget.imagebox,
            },
            valign = "center",
            widget = wibox.container.place,
        },
        -- Text
        {
            {
                text = args.text or "",
                font = args.font or beautiful.font,
                widget = wibox.widget.textbox,
            },
            valign = "center",
            widget = wibox.container.place,
        },
        spacing = spacing,
        layout = wibox.layout.fixed.horizontal,
    }
    
    args.content = content
    return create_navigable_item(args)
end

--- Create an icon-only item (like pinned apps)
-- @param args Configuration with icon_path, size, etc.
-- @return navigable item
local function create_icon_item(args)
    args = args or {}
    
    local icon_size = args.icon_size or dpi(32)
    
    local content = wibox.widget {
        {
            image = args.icon_path,
            resize = true,
            forced_width = icon_size,
            forced_height = icon_size,
            widget = wibox.widget.imagebox,
        },
        halign = "center",
        valign = "center",
        widget = wibox.container.place,
    }
    
    args.content = content
    args.width = args.width or (icon_size + (args.padding or dpi(8)) * 2)
    args.height = args.height or args.width
    
    return create_navigable_item(args)
end

--------------------------------------------------------------------------------
-- Module Export
--------------------------------------------------------------------------------

return setmetatable({
    create = create_navigable_item,
    text = create_text_item,
    icon_text = create_icon_text_item,
    icon = create_icon_item,
}, {
    __call = function(_, ...)
        return create_navigable_item(...)
    end
})
