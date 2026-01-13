--[[
    Base Popup Widget for Awesome WM

    A reusable foundation for popup menus, dialogs, and overlays.
    Provides common functionality that can be extended by specific implementations.

    Features:
    - Configurable popup creation with sensible defaults
    - Keyboard navigation framework (Tab, Arrows, Enter, Escape)
    - Optional fullscreen overlay with dimming
    - Focus management (unfocus clients on open, restore on close)
    - Keygrabber with passthrough for global keybindings
    - Selection/focus tracking for navigable items
    - Show/hide/toggle lifecycle with callbacks

    Usage:
        local base_popup = require("base_popup")

        local my_menu = base_popup.new({
            name = "my_menu",
            width = dpi(400),
            height = dpi(300),
            -- ... other options
        })

        -- Override methods as needed
        function my_menu:create_content()
            return wibox.widget { ... }
        end

        my_menu:init()
        my_menu:show()
]]

local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local wibox = require("wibox")
local dpi = require("beautiful.xresources").apply_dpi

--------------------------------------------------------------------------------
-- base_popup Class
--------------------------------------------------------------------------------

local base_popup = {}
base_popup.__index = base_popup

--- Default configuration values
local DEFAULTS = {
    -- Appearance
    bg = "#1a1a1a",
    border_color = "#333333",
    border_width = dpi(1),
    shape_radius = dpi(16),

    -- Sizing (nil means auto-size)
    width = nil,
    height = nil,
    min_width = nil,
    min_height = nil,
    max_width = nil,
    max_height = nil,

    -- Behavior
    ontop = true,
    visible = false,

    -- Overlay
    show_overlay = false,
    overlay_bg = "#00000050",

    -- Placement
    placement = awful.placement.centered,

    -- Focus
    unfocus_clients = true,

    -- Keyboard
    enable_keygrabber = true,
    passthrough_keys = true,

    -- Navigation
    wrap_navigation = true,  -- Wrap around when reaching end of items

    -- Callbacks
    on_before_show = nil,
    on_show = nil,
    on_hide = nil,
    on_item_selected = nil,
    on_key_press = nil,
}

--------------------------------------------------------------------------------
-- Constructor
--------------------------------------------------------------------------------

--- Create a new base_popup instance
-- @param args Configuration table (see DEFAULTS for options)
-- @return base_popup instance
function base_popup.new(args)
    args = args or {}

    local self = setmetatable({}, base_popup)

    -- Merge defaults with provided args
    for key, default in pairs(DEFAULTS) do
        if args[key] ~= nil then
            self[key] = args[key]
        else
            self[key] = default
        end
    end

    -- Store additional custom args
    self.name = args.name or "base_popup"
    self.theme = args.theme or {}

    -- Internal state
    self._state = {
        popup = nil,
        overlay = nil,
        keygrabber = nil,
        is_visible = false,
        items = {},           -- Navigable items: {widget, data, on_select}
        current_index = 0,    -- Currently focused item (0 = none)
    }

    return self
end

--------------------------------------------------------------------------------
-- Lifecycle Methods
--------------------------------------------------------------------------------

--- Initialize the popup (must be called before show)
-- Creates the popup widget, overlay (if enabled), and keygrabber
function base_popup:init()
    -- Create overlay if enabled
    if self.show_overlay then
        self._state.overlay = self:_create_overlay()
    end

    -- Create the main popup
    self._state.popup = self:_create_popup()

    -- Create keygrabber if enabled
    if self.enable_keygrabber then
        self._state.keygrabber = self:_create_keygrabber()
    end

    -- Allow subclasses to do additional initialization
    if self.on_init then
        self:on_init()
    end

    return self
end

--- Show the popup
function base_popup:show()
    if self._state.is_visible then
        return
    end

    -- Pre-show hook for subclasses
    if self.on_before_show then
        self:on_before_show()
    end

    -- Unfocus all clients if configured
    if self.unfocus_clients and client.focus then
        client.focus = nil
    end

    -- Update content before showing
    local content = self:create_content()
    if content then
        self._state.popup.widget = self:_wrap_content(content)
    end

    -- Show overlay first (if enabled)
    if self._state.overlay then
        self:_update_overlay_geometry()
        self._state.overlay.visible = true
    end

    -- Position off-screen initially to calculate geometry without flicker
    self._state.popup.screen = mouse.screen
    self._state.popup.y = -10000
    self._state.popup.visible = true
    self._state.is_visible = true

    -- Apply placement after geometry is calculated
    gears.timer.start_new(0.01, function()
        if not self._state.is_visible then return false end

        self._state.popup.y = 0
        if self.placement then
            self.placement(self._state.popup, { honor_workarea = true })
        end

        -- Start keygrabber
        if self._state.keygrabber then
            self._state.keygrabber:start()
        end

        -- Reset and initialize selection
        self:reset_selection()

        -- Callback
        if self.on_show then
            self:on_show()
        end

        return false
    end)
end

--- Hide the popup
function base_popup:hide()
    if not self._state.is_visible then
        return
    end

    -- Hide popup
    self._state.popup.visible = false
    self._state.is_visible = false

    -- Hide overlay
    if self._state.overlay then
        self._state.overlay.visible = false
    end

    -- Stop keygrabber
    if self._state.keygrabber then
        self._state.keygrabber:stop()
    end

    -- Focus client under mouse
    local c = awful.mouse.client_under_pointer()
    if c then
        client.focus = c
        c:raise()
    end

    -- Clear selection
    self._state.current_index = 0

    -- Callback
    if self.on_hide then
        self:on_hide()
    end
end

--- Toggle popup visibility
function base_popup:toggle()
    if self._state.is_visible then
        self:hide()
    else
        self:show()
    end
end

--- Check if popup is currently visible
function base_popup:is_visible()
    return self._state.is_visible
end

--------------------------------------------------------------------------------
-- Content Creation (Override in subclasses)
--------------------------------------------------------------------------------

--- Create the popup content widget
-- Override this method in subclasses to provide custom content
-- @return wibox.widget The content widget
function base_popup:create_content()
    -- Default placeholder content
    return wibox.widget {
        {
            text = "Override create_content() to provide content",
            align = "center",
            valign = "center",
            widget = wibox.widget.textbox,
        },
        margins = dpi(20),
        widget = wibox.container.margin,
    }
end

--------------------------------------------------------------------------------
-- Item Management (for keyboard navigation)
--------------------------------------------------------------------------------

--- Register a navigable item
-- @param widget The widget to highlight/focus
-- @param data Optional data associated with the item
-- @param on_select Optional callback when item is selected (Enter pressed)
-- @return index The index of the registered item
function base_popup:register_item(widget, data, on_select)
    local item = {
        widget = widget,
        data = data,
        on_select = on_select,
    }
    table.insert(self._state.items, item)

    -- Set up mouse hover to sync with keyboard navigation
    if widget then
        local index = #self._state.items
        widget:connect_signal("mouse::enter", function()
            self:focus_item(index)
        end)
    end

    return #self._state.items
end

--- Clear all registered items
function base_popup:clear_items()
    self._state.items = {}
    self._state.current_index = 0
end

--- Reset selection to first item (or none)
function base_popup:reset_selection()
    if #self._state.items > 0 then
        self:focus_item(1)
    else
        self._state.current_index = 0
    end
end

--- Focus a specific item by index
-- @param index The item index to focus
function base_popup:focus_item(index)
    if index < 1 or index > #self._state.items then
        return
    end

    -- Unfocus previous item
    if self._state.current_index > 0 and self._state.current_index <= #self._state.items then
        local prev_item = self._state.items[self._state.current_index]
        if prev_item.widget then
            prev_item.widget:emit_signal("item::unfocus")
        end
    end

    -- Focus new item
    self._state.current_index = index
    local item = self._state.items[index]
    if item.widget then
        item.widget:emit_signal("item::focus")
    end

    -- Emit signal for subclasses to handle
    if self._state.popup then
        self._state.popup:emit_signal("property::current_index", index)
    end
end

--- Get the currently focused item
-- @return item The focused item or nil
function base_popup:get_focused_item()
    if self._state.current_index > 0 and self._state.current_index <= #self._state.items then
        return self._state.items[self._state.current_index]
    end
    return nil
end

--- Get the current focus index
function base_popup:get_focus_index()
    return self._state.current_index
end

--- Get total item count
function base_popup:get_item_count()
    return #self._state.items
end

--------------------------------------------------------------------------------
-- Navigation Methods
--------------------------------------------------------------------------------

--- Navigate to the next item
function base_popup:navigate_next()
    if #self._state.items == 0 then return end

    local new_index = self._state.current_index + 1
    if new_index > #self._state.items then
        new_index = self.wrap_navigation and 1 or #self._state.items
    end
    self:focus_item(new_index)
end

--- Navigate to the previous item
function base_popup:navigate_prev()
    if #self._state.items == 0 then return end

    local new_index = self._state.current_index - 1
    if new_index < 1 then
        new_index = self.wrap_navigation and #self._state.items or 1
    end
    self:focus_item(new_index)
end

--- Navigate to first item
function base_popup:navigate_first()
    if #self._state.items > 0 then
        self:focus_item(1)
    end
end

--- Navigate to last item
function base_popup:navigate_last()
    if #self._state.items > 0 then
        self:focus_item(#self._state.items)
    end
end

--- Select the currently focused item
function base_popup:select_current()
    local item = self:get_focused_item()
    if item then
        if item.on_select then
            item.on_select(item.data, self._state.current_index)
        end
        if self.on_item_selected then
            self:on_item_selected(item.data, self._state.current_index)
        end
    end
end

--------------------------------------------------------------------------------
-- Keyboard Handling
--------------------------------------------------------------------------------

--- Handle a key press event
-- Override this in subclasses for custom key handling
-- @param mod Modifier keys
-- @param key The key pressed
-- @return boolean True if key was handled, false to allow passthrough
function base_popup:handle_key(mod, key)
    -- Check for Ctrl modifier
    local is_ctrl = false
    for _, m in ipairs(mod) do
        if m == "Control" then
            is_ctrl = true
            break
        end
    end

    -- Default key handlers
    if key == "Escape" then
        self:hide()
        return true

    elseif key == "Tab" then
        self:navigate_next()
        return true

    elseif key == "ISO_Left_Tab" then  -- Shift+Tab
        self:navigate_prev()
        return true

    elseif key == "Down" then
        self:navigate_next()
        return true

    elseif key == "Up" then
        self:navigate_prev()
        return true

    elseif key == "Home" then
        self:navigate_first()
        return true

    elseif key == "End" then
        self:navigate_last()
        return true

    elseif key == "Return" then
        self:select_current()
        return true
    end

    -- Allow subclass custom handling
    if self.on_key_press then
        local handled = self:on_key_press(mod, key, is_ctrl)
        if handled then
            return true
        end
    end

    return false
end

--------------------------------------------------------------------------------
-- Private Methods
--------------------------------------------------------------------------------

--- Create the popup widget
function base_popup:_create_popup()
    local popup_args = {
        screen = mouse.screen,
        widget = wibox.widget.base.make_widget(),
        bg = self.bg,
        border_color = self.border_color,
        border_width = self.border_width,
        visible = false,
        ontop = self.ontop,
        type = "normal",
    }

    -- Shape
    if self.shape_radius and self.shape_radius > 0 then
        popup_args.shape = function(cr, w, h)
            gears.shape.rounded_rect(cr, w, h, self.shape_radius)
        end
    end

    -- Size constraints
    if self.width then popup_args.width = self.width end
    if self.height then popup_args.height = self.height end
    if self.min_width then popup_args.minimum_width = self.min_width end
    if self.min_height then popup_args.minimum_height = self.min_height end
    if self.max_width then popup_args.maximum_width = self.max_width end
    if self.max_height then popup_args.maximum_height = self.max_height end

    local popup = awful.popup(popup_args)

    return popup
end

--- Wrap content with margins
function base_popup:_wrap_content(content)
    local margin = self.content_margin or dpi(12)

    return wibox.widget {
        content,
        margins = margin,
        widget = wibox.container.margin,
    }
end

--- Create the overlay widget
function base_popup:_create_overlay()
    local overlay = wibox {
        x = 0,
        y = 0,
        visible = false,
        ontop = true,
        type = "utility",
        bg = self.overlay_bg,
    }

    -- Click on overlay to close
    overlay:buttons(gears.table.join(
        awful.button({}, 1, function()
            self:hide()
        end)
    ))

    return overlay
end

--- Update overlay geometry to match screen
function base_popup:_update_overlay_geometry()
    if not self._state.overlay then return end

    local screen_geom = mouse.screen.geometry
    self._state.overlay.screen = mouse.screen
    self._state.overlay.x = screen_geom.x
    self._state.overlay.y = screen_geom.y
    self._state.overlay.width = screen_geom.width
    self._state.overlay.height = screen_geom.height
end

--- Create the keygrabber
function base_popup:_create_keygrabber()
    local self_ref = self  -- Capture reference for closure

    return awful.keygrabber {
        autostart = false,

        keypressed_callback = function(_, mod, key)
            local handled = self_ref:handle_key(mod, key)

            -- Passthrough unhandled keys to global keybindings
            if not handled and self_ref.passthrough_keys then
                self_ref:_execute_keybind(key, mod)
            end
        end,

        stop_callback = function()
            -- Ensure popup is hidden when grabber stops
            if self_ref._state.is_visible then
                self_ref._state.popup.visible = false
                self_ref._state.is_visible = false
            end
        end,
    }
end

--- Execute a global keybinding
function base_popup:_execute_keybind(key, mod)
    -- Use the global execute_keybind if available
    if execute_keybind then
        execute_keybind(key, mod)
        return
    end

    -- Fallback implementation
    for _, binding in ipairs(root.keys()) do
        if awful.key.match(binding, mod, key) then
            local lua_key = binding._private._legacy_convert_to
            if lua_key and lua_key.trigger then
                lua_key:trigger()
                return
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Utility Methods
--------------------------------------------------------------------------------

--- Get the popup widget (for direct access if needed)
function base_popup:get_popup()
    return self._state.popup
end

--- Get the overlay widget
function base_popup:get_overlay()
    return self._state.overlay
end

--- Refresh the popup content
function base_popup:refresh()
    if self._state.popup then
        local content = self:create_content()
        if content then
            self._state.popup.widget = self:_wrap_content(content)
        end
    end
end

--- Update popup size
function base_popup:set_size(width, height)
    if self._state.popup then
        if width then self._state.popup.width = width end
        if height then self._state.popup.height = height end
    end
end

--- Connect to popup signals
function base_popup:connect_signal(signal, callback)
    if self._state.popup then
        self._state.popup:connect_signal(signal, callback)
    end
end

--------------------------------------------------------------------------------
-- Module Export
--------------------------------------------------------------------------------

return base_popup