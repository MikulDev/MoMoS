--[[
    Popup Widget System for Awesome WM

    A standardized way to create wibar widgets with popup menus.
    Features:
    - Consistent popup positioning with configurable margins
    - Mouse-leave auto-hide behavior (popup stays visible when hovering button OR popup)
    - Shared hover state management between button and popup

    Usage:
        local popup_widget = require("popup_widget")

        local my_widget = popup_widget.create({
            button = my_button_widget,
            popup = my_popup_widget,  -- or popup_create_fn for lazy creation
            popup_create_fn = function() return create_my_popup() end,
            margin = dpi(10),  -- margin from screen edges
            position = "top_right",  -- top_right, top_left, bottom_right, bottom_left
            hide_delay = 0.1,  -- delay before hiding on mouse leave
            on_show = function(popup) end,  -- optional callback
            on_hide = function(popup) end,  -- optional callback
        })
]]

local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local wibox = require("wibox")
local dpi = require("beautiful.xresources").apply_dpi

local popup_widget = {}

-- Default configuration
local defaults = {
    margin = dpi(10),
    position = "top_right",
    hide_delay = 0.1,
}

-- Calculate popup position based on screen geometry and position setting
local function calculate_position(popup, screen, position, margin)
    local geo = screen.geometry
    local workarea = screen.workarea
    local wibar_height = beautiful.wibar_height or dpi(28)

    local x, y

    if position == "top_right" then
        x = geo.x + geo.width - popup.width - margin
        y = workarea.y + margin
    elseif position == "top_left" then
        x = geo.x + margin
        y = workarea.y + margin
    elseif position == "bottom_right" then
        x = geo.x + geo.width - popup.width - margin
        y = geo.y + geo.height - popup.height - margin
    elseif position == "bottom_left" then
        x = geo.x + margin
        y = geo.y + geo.height - popup.height - margin
    else
        -- Default to top_right
        x = geo.x + geo.width - popup.width - margin
        y = workarea.y + margin
    end

    return x, y
end

-- Create a popup widget with standardized behavior
function popup_widget.create(args)
    args = args or {}

    local button = args.button
    local popup = args.popup
    local popup_create_fn = args.popup_create_fn
    local margin = args.margin or defaults.margin
    local position = args.position or defaults.position
    local hide_delay = args.hide_delay or defaults.hide_delay
    local on_show = args.on_show
    local on_hide = args.on_hide

    -- State management
    local state = {
        button_hovered = false,
        popup_hovered = false,
        hide_timer = nil,
        popup = popup,
    }

    -- Get or create the popup
    local function get_popup()
        if not state.popup and popup_create_fn then
            state.popup = popup_create_fn()
            setup_popup_signals(state.popup)
        end
        return state.popup
    end

    -- Check if we should hide
    local function check_hide()
        if not state.button_hovered and not state.popup_hovered then
            local p = state.popup
            if p and p.visible then
                p.visible = false
                if on_hide then on_hide(p) end
            end
        end
    end

    -- Start hide timer
    local function start_hide_timer()
        if state.hide_timer then
            state.hide_timer:stop()
        end
        state.hide_timer = gears.timer.start_new(hide_delay, function()
            check_hide()
            return false
        end)
    end

    -- Cancel hide timer
    local function cancel_hide_timer()
        if state.hide_timer then
            state.hide_timer:stop()
            state.hide_timer = nil
        end
    end

    -- Setup popup mouse signals
    function setup_popup_signals(p)
        if not p then return end

        p:connect_signal("mouse::enter", function()
            state.popup_hovered = true
            cancel_hide_timer()
        end)

        p:connect_signal("mouse::leave", function()
            state.popup_hovered = false
            start_hide_timer()
        end)
    end

    -- Position and show the popup
    local function show_popup()
        local p = get_popup()
        if not p then return end

        local widget_screen = mouse.screen
        if not widget_screen then return end

        -- First render pass to get proper sizing
        p.visible = true
        p.visible = false

        -- Position after a slight delay to ensure rendering
        gears.timer.start_new(0.01, function()
            local x, y = calculate_position(p, widget_screen, position, margin)
            p.x = x
            p.y = y
            p.visible = true
            if on_show then on_show(p) end
            return false
        end)
    end

    -- Hide the popup
    local function hide_popup()
        local p = state.popup
        if p and p.visible then
            p.visible = false
            if on_hide then on_hide(p) end
        end
    end

    -- Toggle popup visibility
    local function toggle_popup()
        local p = get_popup()
        if p and p.visible then
            hide_popup()
        else
            show_popup()
        end
    end

    -- Setup button signals for hover behavior
    if button then
        button:connect_signal("mouse::enter", function()
            state.button_hovered = true
            cancel_hide_timer()
        end)

        button:connect_signal("mouse::leave", function()
            state.button_hovered = false
            start_hide_timer()
        end)
    end

    -- Setup initial popup signals if popup is provided
    if popup then
        setup_popup_signals(popup)
    end

    -- Return controller interface
    return {
        button = button,

        -- Get the popup (creates if necessary)
        get_popup = get_popup,

        -- Show/hide/toggle
        show = show_popup,
        hide = hide_popup,
        toggle = toggle_popup,

        -- Check visibility
        is_visible = function()
            return state.popup and state.popup.visible
        end,

        -- Update hover state (for external widgets that need to participate)
        set_button_hovered = function(hovered)
            state.button_hovered = hovered
            if hovered then
                cancel_hide_timer()
            else
                start_hide_timer()
            end
        end,

        set_popup_hovered = function(hovered)
            state.popup_hovered = hovered
            if hovered then
                cancel_hide_timer()
            else
                start_hide_timer()
            end
        end,

        -- Attach additional widgets to share hover state
        attach_widget = function(widget)
            widget:connect_signal("mouse::enter", function()
                state.popup_hovered = true
                cancel_hide_timer()
            end)
            widget:connect_signal("mouse::leave", function()
                state.popup_hovered = false
                start_hide_timer()
            end)
        end,

        -- Get state (for debugging)
        get_state = function()
            return {
                button_hovered = state.button_hovered,
                popup_hovered = state.popup_hovered,
                visible = state.popup and state.popup.visible
            }
        end,
    }
end

-- Helper to wrap an existing popup with the hover behavior
-- This is useful for migrating existing popups to the new system
function popup_widget.wrap_popup(popup, args)
    args = args or {}
    args.popup = popup
    return popup_widget.create(args)
end

-- Helper to create a simple popup wibox with standard styling
function popup_widget.create_popup(args)
    args = args or {}

    local theme = args.theme or {}

    return awful.popup {
        ontop = true,
        visible = false,
        shape = function(cr, width, height)
            gears.shape.rounded_rect(cr, width, height, args.shape_radius or dpi(12))
        end,
        border_width = args.border_width or dpi(1),
        border_color = args.border_color or theme.border or "#333333",
        bg = args.bg or theme.bg or "#1e1e2e",
        widget = args.widget,
    }
end

return popup_widget