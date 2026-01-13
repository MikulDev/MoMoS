--[[
    Scrollable List Widget for Awesome WM
    
    A reusable scrollable list that integrates with BasePopup.
    Handles virtualized rendering, scroll state, and keyboard navigation.
    
    Features:
    - Virtualized rendering (only renders visible items)
    - Mouse wheel scrolling
    - Keyboard navigation with auto-scroll
    - Configurable item creation via factory function
    - Header and footer support
    
    Usage:
        local ScrollableList = require("scrollable_list")
        
        local list = ScrollableList.new({
            items_per_page = 10,
            item_height = dpi(48),
            create_item = function(data, index)
                return create_my_item(data)
            end,
        })
        
        list:set_data({ item1, item2, ... })
        
        -- Get the widget
        local widget = list:get_widget()
]]

local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local wibox = require("wibox")
local dpi = require("beautiful.xresources").apply_dpi

--------------------------------------------------------------------------------
-- ScrollableList Class
--------------------------------------------------------------------------------

local ScrollableList = {}
ScrollableList.__index = ScrollableList

--- Default configuration
local DEFAULTS = {
    items_per_page = 10,
    item_height = dpi(48),
    item_spacing = dpi(4),
    scroll_step = 1,
    width = nil,
    
    -- Styling
    bg = "transparent",
    
    -- Callbacks
    create_item = nil,       -- function(data, index) -> widget
    on_item_focus = nil,     -- function(data, index)
    on_item_select = nil,    -- function(data, index)
    on_scroll = nil,         -- function(start_idx, visible_count)
}

--------------------------------------------------------------------------------
-- Constructor
--------------------------------------------------------------------------------

--- Create a new ScrollableList
-- @param args Configuration table
-- @return ScrollableList instance
function ScrollableList.new(args)
    args = args or {}
    
    local self = setmetatable({}, ScrollableList)
    
    -- Merge defaults
    for key, default in pairs(DEFAULTS) do
        if args[key] ~= nil then
            self[key] = args[key]
        else
            self[key] = default
        end
    end
    
    -- Internal state
    self._state = {
        data = {},              -- All data items
        start_idx = 1,          -- First visible item index
        focused_idx = 0,        -- Currently focused item (global index)
        rendered_items = {},    -- Currently rendered item widgets
        widget = nil,           -- The main list widget
        layout = nil,           -- The layout containing items
        header = nil,           -- Optional header widget
        footer = nil,           -- Optional footer widget
        popup = nil,            -- Reference to parent BasePopup
    }
    
    -- Build the widget
    self:_build_widget()
    
    return self
end

--------------------------------------------------------------------------------
-- Public Methods
--------------------------------------------------------------------------------

--- Set the data source
-- @param data Array of data items
function ScrollableList:set_data(data)
    self._state.data = data or {}
    self._state.start_idx = 1
    self._state.focused_idx = 0
    self:refresh()
end

--- Get current data
function ScrollableList:get_data()
    return self._state.data
end

--- Get data count
function ScrollableList:get_count()
    return #self._state.data
end

--- Set the parent popup (for item registration)
-- @param popup BasePopup instance
function ScrollableList:set_popup(popup)
    self._state.popup = popup
end

--- Set optional header widget
-- @param widget Header widget
function ScrollableList:set_header(widget)
    self._state.header = widget
    self:_rebuild_container()
end

--- Set optional footer widget
-- @param widget Footer widget
function ScrollableList:set_footer(widget)
    self._state.footer = widget
    self:_rebuild_container()
end

--- Get the widget
-- @return wibox.widget
function ScrollableList:get_widget()
    return self._state.widget
end

--- Refresh the list (re-render visible items)
function ScrollableList:refresh()
    self:_render_visible_items()
end

--- Scroll up by step
function ScrollableList:scroll_up()
    if self._state.start_idx > 1 then
        self._state.start_idx = math.max(1, self._state.start_idx - self.scroll_step)
        self:refresh()
        
        if self.on_scroll then
            self.on_scroll(self._state.start_idx, self.items_per_page)
        end
    end
end

--- Scroll down by step
function ScrollableList:scroll_down()
    local max_start = math.max(1, #self._state.data - self.items_per_page + 1)
    if self._state.start_idx < max_start then
        self._state.start_idx = math.min(max_start, self._state.start_idx + self.scroll_step)
        self:refresh()
        
        if self.on_scroll then
            self.on_scroll(self._state.start_idx, self.items_per_page)
        end
    end
end

--- Scroll to show a specific index
-- @param index Global index to ensure is visible
function ScrollableList:ensure_visible(index)
    if index < 1 or index > #self._state.data then
        return
    end
    
    -- Check if already visible
    local end_idx = self._state.start_idx + self.items_per_page - 1
    
    if index < self._state.start_idx then
        -- Scroll up
        self._state.start_idx = index
        self:refresh()
    elseif index > end_idx then
        -- Scroll down
        self._state.start_idx = index - self.items_per_page + 1
        self:refresh()
    end
end

--- Focus a specific item by global index
-- @param index Global index to focus
function ScrollableList:focus_item(index)
    if index < 1 or index > #self._state.data then
        return
    end
    
    -- Ensure visible first
    self:ensure_visible(index)
    
    -- Unfocus previous
    if self._state.focused_idx > 0 then
        local prev_local = self._state.focused_idx - self._state.start_idx + 1
        if prev_local >= 1 and prev_local <= #self._state.rendered_items then
            local prev_item = self._state.rendered_items[prev_local]
            if prev_item and prev_item.widget then
                prev_item.widget:emit_signal("item::unfocus")
            end
        end
    end
    
    -- Focus new
    self._state.focused_idx = index
    local local_idx = index - self._state.start_idx + 1
    if local_idx >= 1 and local_idx <= #self._state.rendered_items then
        local item = self._state.rendered_items[local_idx]
        if item and item.widget then
            item.widget:emit_signal("item::focus")
        end
    end
    
    if self.on_item_focus then
        self.on_item_focus(self._state.data[index], index)
    end
end

--- Navigate to next item
function ScrollableList:navigate_next()
    local new_idx = self._state.focused_idx + 1
    if new_idx > #self._state.data then
        new_idx = 1  -- Wrap
    end
    self:focus_item(new_idx)
end

--- Navigate to previous item
function ScrollableList:navigate_prev()
    local new_idx = self._state.focused_idx - 1
    if new_idx < 1 then
        new_idx = #self._state.data  -- Wrap
    end
    self:focus_item(new_idx)
end

--- Get currently focused data
function ScrollableList:get_focused_data()
    if self._state.focused_idx > 0 and self._state.focused_idx <= #self._state.data then
        return self._state.data[self._state.focused_idx]
    end
    return nil
end

--- Get focused index
function ScrollableList:get_focused_index()
    return self._state.focused_idx
end

--- Select (activate) the currently focused item
function ScrollableList:select_current()
    local data = self:get_focused_data()
    if data and self.on_item_select then
        self.on_item_select(data, self._state.focused_idx)
    end
end

--------------------------------------------------------------------------------
-- Private Methods
--------------------------------------------------------------------------------

--- Build the main widget structure
function ScrollableList:_build_widget()
    -- Create the layout for items
    self._state.layout = wibox.widget {
        spacing = self.item_spacing,
        layout = wibox.layout.fixed.vertical,
    }
    
    -- Create container
    self:_rebuild_container()
end

--- Rebuild the container with header/footer
function ScrollableList:_rebuild_container()
    local container = wibox.widget {
        spacing = self.item_spacing,
        layout = wibox.layout.fixed.vertical,
    }
    
    -- Add header if present
    if self._state.header then
        container:add(self._state.header)
    end
    
    -- Add the items layout
    container:add(self._state.layout)
    
    -- Add footer if present
    if self._state.footer then
        container:add(self._state.footer)
    end
    
    -- Wrap with scroll handling
    self._state.widget = wibox.widget {
        container,
        bg = self.bg,
        widget = wibox.container.background,
    }
    
    -- Width constraint
    if self.width then
        self._state.widget = wibox.widget {
            self._state.widget,
            forced_width = self.width,
            widget = wibox.container.constraint,
        }
    end
    
    -- Add scroll buttons
    self._state.widget:buttons(gears.table.join(
        awful.button({}, 4, function()  -- Scroll up
            self:scroll_up()
        end),
        awful.button({}, 5, function()  -- Scroll down
            self:scroll_down()
        end)
    ))
end

--- Render only the visible items
function ScrollableList:_render_visible_items()
    -- Clear current layout
    self._state.layout:reset()
    self._state.rendered_items = {}
    
    -- Clear popup items if connected
    if self._state.popup then
        self._state.popup:clear_items()
    end
    
    -- Calculate visible range
    local end_idx = math.min(
        self._state.start_idx + self.items_per_page - 1,
        #self._state.data
    )
    
    -- Render each visible item
    for i = self._state.start_idx, end_idx do
        local data = self._state.data[i]
        local item = nil
        
        -- Create item widget via factory
        if self.create_item then
            item = self.create_item(data, i)
        else
            -- Default simple item
            item = self:_create_default_item(data, i)
        end
        
        if item then
            -- Store rendered item
            table.insert(self._state.rendered_items, item)
            
            -- Add to layout
            local widget = item.widget or item
            self._state.layout:add(widget)
            
            -- Register with popup if connected
            if self._state.popup and item.widget then
                local idx = i
                self._state.popup:register_item(
                    item.widget,
                    data,
                    function()
                        if self.on_item_select then
                            self.on_item_select(data, idx)
                        end
                    end
                )
            end
            
            -- Restore focus state if this was focused
            if i == self._state.focused_idx and item.widget then
                item.widget:emit_signal("item::focus")
            end
        end
    end
end

--- Create a default item (used when no factory provided)
function ScrollableList:_create_default_item(data, index)
    local text = tostring(data)
    if type(data) == "table" then
        text = data.name or data.text or data.title or tostring(data)
    end
    
    local widget = wibox.widget {
        {
            {
                text = text,
                widget = wibox.widget.textbox,
            },
            margins = dpi(8),
            widget = wibox.container.margin,
        },
        bg = beautiful.bg_normal or "#1a1a1a",
        fg = beautiful.fg_normal or "#ffffff",
        widget = wibox.container.background,
    }
    
    -- Focus signals
    widget:connect_signal("item::focus", function()
        widget.bg = beautiful.bg_focus or "#2a2a2a"
    end)
    
    widget:connect_signal("item::unfocus", function()
        widget.bg = beautiful.bg_normal or "#1a1a1a"
    end)
    
    return { widget = widget }
end

--------------------------------------------------------------------------------
-- Module Export
--------------------------------------------------------------------------------

return ScrollableList
