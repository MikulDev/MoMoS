--[[
    Shutdown Menu - Refactored with BasePopup

    This demonstrates how to use the BasePopup system to create
    a clean, maintainable popup menu.
]]

local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local wibox = require("wibox")
local dpi = require("beautiful.xresources").apply_dpi

local BasePopup = require("base_popup")
local NavItem = require("navigable_item")

local config_dir = gears.filesystem.get_configuration_dir()
local icon_dir = config_dir .. "theme-icons/"
local theme = load_util("theme")

--------------------------------------------------------------------------------
-- Shutdown Menu Implementation
--------------------------------------------------------------------------------

local shutdown_menu = {}
shutdown_menu.__index = shutdown_menu
setmetatable(shutdown_menu, { __index = BasePopup })

--- Actions configuration
local ACTIONS = {
    {
        name = "Shut Down",
        icon = icon_dir .. "shutdown.png",
        command = "shutdown now"
    },
    {
        name = "Restart",
        icon = icon_dir .. "restart.png",
        command = "reboot"
    },
    {
        name = "Sleep",
        icon = icon_dir .. "sleep.png",
        command = "systemctl suspend"
    }
}

--- Create a new shutdown menu
function shutdown_menu.new()
    -- Create base popup with our configuration
    local self = BasePopup.new({
        name = "shutdown",

        -- Appearance
        bg = theme.shutdown.bg,
        border_color = theme.shutdown.border,
        shape_radius = dpi(16),

        -- Overlay
        show_overlay = true,
        overlay_bg = "#00000050",

        -- Behavior
        wrap_navigation = true,

        -- Content margin
        content_margin = dpi(16),
    })

    setmetatable(self, shutdown_menu)

    -- Store action widgets for focus updates
    self._action_items = {}

    return self
end

--- Create the content widget
function shutdown_menu:create_content()
    -- Clear previous items
    self:clear_items()
    self._action_items = {}

    -- Create horizontal layout for action buttons
    local buttons_layout = wibox.widget {
        spacing = dpi(16),
        layout = wibox.layout.fixed.horizontal,
    }

    -- Create each action button
    for i, action in ipairs(ACTIONS) do
        local button_item = self:_create_action_button(action, i)
        buttons_layout:add(button_item.container)
        table.insert(self._action_items, button_item)

        -- Register with navigation system
        self:register_item(
            button_item.button,
            action,
            function(data)
                awful.spawn(data.command)
                self:hide()
            end
        )
    end

    return wibox.widget {
        buttons_layout,
        halign = "center",
        widget = wibox.container.place,
    }
end

--- Create a single action button
function shutdown_menu:_create_action_button(action, index)
    local item = {}

    -- Icon button
    item.button = wibox.widget {
        {
            {
                {
                    image = action.icon,
                    resize = true,
                    forced_width = dpi(30),
                    forced_height = dpi(30),
                    widget = wibox.widget.imagebox,
                },
                halign = "center",
                valign = "center",
                widget = wibox.container.place,
            },
            margins = dpi(16),
            widget = wibox.container.margin,
        },
        bg = theme.shutdown.button_bg,
        shape = function(cr, w, h)
            gears.shape.rounded_rect(cr, w, h, dpi(12))
        end,
        shape_border_width = dpi(1),
        shape_border_color = theme.shutdown.border,
        forced_width = dpi(64),
        forced_height = dpi(64),
        widget = wibox.container.background,
    }

    -- Label
    item.label = wibox.widget {
        {
            text = action.name,
            font = font_with_size(12),
            align = "center",
            widget = wibox.widget.textbox,
        },
        fg = theme.shutdown.fg,
        widget = wibox.container.background,
    }

    -- Focus/unfocus handlers
    item.button:connect_signal("item::focus", function()
        item.button.bg = theme.shutdown.button_bg_focus
        item.button.shape_border_color = theme.shutdown.border_focus
        item.label.fg = theme.shutdown.fg_focus
    end)

    item.button:connect_signal("item::unfocus", function()
        item.button.bg = theme.shutdown.button_bg
        item.button.shape_border_color = theme.shutdown.border
        item.label.fg = theme.shutdown.fg
    end)
    
    -- Mouse hover
    item.button:connect_signal("mouse::enter", function()
        self:focus_item(index)
    end)

    -- Click handler
    item.button:buttons(gears.table.join(
        awful.button({}, 1, function()
            awful.spawn(action.command)
            self:hide()
        end)
    ))

    -- Add hover cursor
    if add_hover_cursor then
        add_hover_cursor(item.button)
    end

    -- Container with button and label
    item.container = wibox.widget {
        {
            {
                item.button,
                halign = "center",
                widget = wibox.container.place,
            },
            item.label,
            spacing = dpi(8),
            layout = wibox.layout.fixed.vertical,
        },
        margins = dpi(8),
        widget = wibox.container.margin,
    }

    return item
end

--- Custom key handling (extends base)
function shutdown_menu:on_key_press(mod, key, is_ctrl)
    -- Left/Right navigation (in addition to Tab/Up/Down)
    if key == "Left" then
        self:navigate_prev()
        return true
    elseif key == "Right" then
        self:navigate_next()
        return true
    end

    return false
end

--------------------------------------------------------------------------------
-- Module Interface (maintains compatibility with existing code)
--------------------------------------------------------------------------------

local shutdown_instance = nil

local function shutdown_init()
    shutdown_instance = shutdown_menu.new()
    shutdown_instance:init()
    return shutdown_instance:get_popup()
end

local function shutdown_show()
    if shutdown_instance then
        shutdown_instance:show()
    end
end

local function shutdown_hide()
    if shutdown_instance then
        shutdown_instance:hide()
    end
end

local function shutdown_toggle()
    if shutdown_instance then
        shutdown_instance:toggle()
    end
end

return {
    init = shutdown_init,
    show = shutdown_show,
    hide = shutdown_hide,
    toggle = shutdown_toggle,

    -- Also export the class for direct use
    shutdown_menu = shutdown_menu,
}