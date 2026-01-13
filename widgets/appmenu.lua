--[[
    Application Menu - Refactored with BasePopup

    A full-featured application launcher with:
    - Search filtering
    - Pinned apps section
    - Scrollable app list
    - Pin/unpin functionality
    - Desktop file info viewer
    - Ctrl+click for sudo execution
    - Keyboard navigation between sections
]]

local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local wibox = require("wibox")
local dpi = require("beautiful.xresources").apply_dpi
local naughty = require("naughty")

local BasePopup = require("base_popup")

local config_dir = gears.filesystem.get_configuration_dir()
local icon_dir = config_dir .. "theme-icons/"
local theme = load_util("theme")
local create_text_input = load_widget("text_input")

--------------------------------------------------------------------------------
-- app_menu Class
--------------------------------------------------------------------------------

local app_menu = {}
app_menu.__index = app_menu
setmetatable(app_menu, { __index = BasePopup })

--- Configuration
local CONFIG = {
    visible_entries = 10,
    max_pinned = 8,
    font = font_with_size(13),
    width = dpi(500),
    height_with_pinned = dpi(672),
    height_without_pinned = dpi(590),
    icons = {
        search = icon_dir .. "search.png",
        pin = icon_dir .. "pin.svg",
        pinned = icon_dir .. "unpin.png",
        info = icon_dir .. "folder.png",
    },
}

--------------------------------------------------------------------------------
-- Constructor
--------------------------------------------------------------------------------

function app_menu.new()
    local self = BasePopup.new({
        name = "appmenu",

        -- Appearance
        bg = theme.appmenu.bg,
        border_color = theme.appmenu.border,
        border_width = dpi(1),
        shape_radius = dpi(16),

        -- Sizing
        width = CONFIG.width,
        min_width = CONFIG.width,
        max_width = CONFIG.width,

        -- We'll handle navigation ourselves due to complexity
        enable_keygrabber = false,
    })
    
    setmetatable(self, app_menu)
    
    -- App menu specific state
    self._menu = {
        desktop_entries = {},
        filtered_list = {},
        pinned_apps = {},

        -- Scroll state
        current_start = 1,

        -- Focus state
        -- type: "pinned" or "apps"
        -- index: which item in that section
        -- pin_focused: whether the pin button is focused (apps only)
        -- info_focused: whether the info button is focused (apps only)
        focus = {
            type = "pinned",
            index = 1,
            pin_focused = false,
            info_focused = false,
        },

        -- Modifier state
        control_pressed = false,

        -- Widget references
        search_input = nil,
        pinned_widgets = {},
        app_widgets = {},
    }

    return self
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function app_menu:init()
    -- Call parent init (creates popup, overlay, etc.)
    BasePopup.init(self)
    
    -- Load pinned apps from persistent storage
    self:_load_pinned_apps()

    -- Scan desktop files
    self:_scan_desktop_files()

    -- Create custom keygrabber with modifier tracking
    self._menu.keygrabber = awful.keygrabber {
        autostart = false,

        keypressed_callback = function(_, mod, key)
            -- Track control key state
            if key == "Control_L" or key == "Control_R" then
                self._menu.control_pressed = true
                self:_emit_focus_update()
                return
            end

            -- Let text input handle the key first
            if self._menu.search_input and self._menu.search_input:handle_key(mod, key) then
                return
            end

            -- Handle escape
            if key == "Escape" then
                self:hide()
                return
            end

            -- Handle navigation keys
            if key == "Up" or key == "Down" or key == "Left" or key == "Right" or
               key == "Return" or key == "Home" or key == "End" or key == "Tab" then
                self:_handle_navigation(mod, key)
                return
            end

            -- Passthrough other keys to global bindings
            if execute_keybind then
                execute_keybind(key, mod)
            end
        end,

        keyreleased_callback = function(_, mod, key)
            if key == "Control_L" or key == "Control_R" then
                self._menu.control_pressed = false
                self:_emit_focus_update()
            end
        end,

        stop_callback = function()
            if self._state.is_visible then
                self._state.popup.visible = false
                self._state.is_visible = false
            end
        end,
    }
    
    return self
end

--------------------------------------------------------------------------------
-- Lifecycle Hooks
--------------------------------------------------------------------------------

--- Called before show() does its work
function app_menu:on_before_show()
    -- Rescan desktop files (in case apps were installed/removed)
    self:_scan_desktop_files()

    -- Reset state
    self._menu.control_pressed = false
    self._menu.current_start = 1
    self._menu.focus = {
        type = #self._menu.pinned_apps > 0 and "pinned" or "apps",
        index = 1,
        pin_focused = false,
        info_focused = false,
    }
    self:_emit_focus_update()

    -- Reset search
    if self._menu.search_input then
        self._menu.search_input:set_text("")
    end
    self:_update_filtered_list("")

    -- Update height based on pinned apps
    local height = #self._menu.pinned_apps > 0
        and CONFIG.height_with_pinned
        or CONFIG.height_without_pinned
    self._state.popup.minimum_height = height
    self._state.popup.maximum_height = height
end

--- Called after popup is positioned and visible
function app_menu:on_show()
    -- Start our custom keygrabber (base class keygrabber is disabled)
    if self._menu.keygrabber then
        self._menu.keygrabber:start()
    end

    -- Emit initial focus
    self:_emit_focus_update()
end

--- Override content wrapping to use constraint
function app_menu:_wrap_content(content)
    local height = #self._menu.pinned_apps > 0
        and CONFIG.height_with_pinned
        or CONFIG.height_without_pinned
    return wibox.container.constraint(content, "exact", CONFIG.width, height)
end

--- Override show to call parent
function app_menu:show()
    BasePopup.show(self)
end

function app_menu:hide()
    if not self._state.is_visible then
        return
    end
    
    self._state.popup.visible = false
    self._state.is_visible = false

    if self._menu.keygrabber then
        self._menu.keygrabber:stop()
    end

    -- Restore focus to client under mouse
    local c = awful.mouse.client_under_pointer()
    if c then
        client.focus = c
        c:raise()
    end
end

--- Override refresh to maintain constraint wrapper
function app_menu:refresh()
    if not self._state.popup then return end

    -- Recalculate height in case pinned apps changed
    local height = #self._menu.pinned_apps > 0
        and CONFIG.height_with_pinned
        or CONFIG.height_without_pinned
    self._state.popup.minimum_height = height
    self._state.popup.maximum_height = height

    -- Rebuild content with constraint wrapper
    local content = self:create_content()
    self._state.popup.widget = self:_wrap_content(content)

    -- Re-emit focus update after widgets are rebuilt
    gears.timer.start_new(0.01, function()
        self:_emit_focus_update()
        return false
    end)
end

--------------------------------------------------------------------------------
-- Content Creation
--------------------------------------------------------------------------------

function app_menu:create_content()
    -- Clear widget references
    self._menu.pinned_widgets = {}
    self._menu.app_widgets = {}

    -- Create search input if not exists
    if not self._menu.search_input then
        self._menu.search_input = create_text_input({
            disable_arrows = true,
            font = CONFIG.font,
            height = dpi(24),
            on_text_change = function(new_text)
                if new_text ~= "" and new_text ~= nil then
                    self._menu.current_start = 1
                    self._menu.focus = {
                        type = "apps",
                        index = 1,
                        pin_focused = false,
                        info_focused = false
                    }
                    self:_update_filtered_list(new_text)
                    self:_ensure_focused_visible()
                    self:refresh()
                end
            end
        })
    end

    -- Build the layout
    local layout = wibox.layout.fixed.vertical()
    layout.spacing = dpi(4)

    -- Pinned apps section (if any)
    if #self._menu.pinned_apps > 0 then
        layout:add(self:_create_pinned_section())
    end

    -- Search box
    layout:add(self:_create_search_box())

    -- App list
    layout:add(self:_create_app_list())

    return layout
end

function app_menu:_create_pinned_section()
    local row = wibox.widget {
        layout = wibox.layout.fixed.horizontal,
        spacing = dpi(8),
    }

    for i, app in ipairs(self._menu.pinned_apps) do
        local icon = self:_create_pinned_icon(app, i)
        row:add(icon)
        self._menu.pinned_widgets[i] = icon
    end

    local separator = wibox.widget {
        widget = wibox.widget.separator,
        orientation = "horizontal",
        forced_height = 1,
        color = theme.appmenu.button_border .. "33",
        span_ratio = 0.98,
    }

    return wibox.widget {
        {
            {
                {
                    row,
                    margins = dpi(8),
                    widget = wibox.container.margin,
                },
                margins = dpi(8),
                widget = wibox.container.margin,
            },
            separator,
            layout = wibox.layout.fixed.vertical,
            spacing = dpi(1),
        },
        bg = theme.appmenu.bg,
        widget = wibox.container.background,
    }
end

function app_menu:_create_pinned_icon(app, index)
    local icon_widget = create_image_button({
        image_path = app.icon,
        fallback_text = "◫",
        image_size = dpi(32),
        padding = dpi(6),
        bg_color = theme.appmenu.button_bg,
        hover_bg = theme.appmenu.button_bg_focus,
        border_color = theme.appmenu.button_border .. "33",
        hover_border = theme.appmenu.button_border_focus,
        shape_radius = dpi(8),
        on_click = function()
            if self._menu.control_pressed then
                self:_run_with_sudo(app.exec)
            else
                awful.spawn(app.exec)
            end
            self:hide()
            return true
        end,
        on_right_click = function()
            self:_remove_pinned(index)
        end,
    })

    -- Custom focus update
    function icon_widget:update_menu_focus(menu)
        local focus = menu._menu.focus
        if focus.type == "pinned" and focus.index == index then
            self:emit_signal("button::focus")
            if menu._menu.control_pressed then
                gears.timer.start_new(0.01, function()
                    self.shape_border_color = theme.appmenu.button_border_sudo
                    self.bg = theme.appmenu.button_bg_sudo
                    return false
                end)
            end
        else
            self:emit_signal("button::unfocus")
        end
    end

    -- Mouse enter changes focus
    icon_widget:connect_signal("mouse::enter", function()
        self._menu.focus = { type = "pinned", index = index, pin_focused = false }
        self:_emit_focus_update()
    end)

    return icon_widget
end

function app_menu:_create_search_box()
    local search_icon = wibox.widget {
        {
            image = CONFIG.icons.search,
            resize = true,
            forced_width = dpi(18),
            forced_height = dpi(18),
            opacity = 0.5,
            widget = wibox.widget.imagebox,
        },
        valign = "center",
        widget = wibox.container.place,
    }

    local search_content = wibox.widget {
        search_icon,
        {
            self._menu.search_input.background,
            bottom = dpi(4),
            widget = wibox.container.margin,
        },
        spacing = dpi(8),
        layout = wibox.layout.fixed.horizontal,
    }
    
    return wibox.widget {
        {
            {
                search_content,
                margins = dpi(12),
                widget = wibox.container.margin,
            },
            bg = theme.appmenu.bg,
            shape = function(cr, w, h)
                gears.shape.rounded_rect(cr, w, h, dpi(15))
            end,
            shape_border_width = dpi(1),
            shape_border_color = theme.appmenu.button_border .. "33",
            widget = wibox.container.background,
        },
        left = dpi(12),
        right = dpi(12),
        top = dpi(10),
        bottom = dpi(10),
        widget = wibox.container.margin,
    }
end

function app_menu:_create_app_list()
    local list = wibox.widget {
        layout = wibox.layout.fixed.vertical,
        spacing = dpi(6),
    }

    local start_idx = self._menu.current_start
    local end_idx = math.min(
        start_idx + CONFIG.visible_entries - 1,
        #self._menu.filtered_list
    )

    for i = start_idx, end_idx do
        local app = self._menu.filtered_list[i]
        if app then
            local entry = self:_create_app_entry(app, i)
            list:add(entry.container)
            self._menu.app_widgets[i] = entry
        end
    end

    -- Add scroll buttons
    list:buttons(gears.table.join(
        awful.button({}, 4, function() self:_scroll_list(-1) end),
        awful.button({}, 5, function() self:_scroll_list(1) end)
    ))

    return wibox.widget {
        list,
        margins = dpi(4),
        widget = wibox.container.margin,
    }
end

function app_menu:_create_app_entry(app, index)
    local entry = {
        is_pinned = self:_is_app_pinned(app),
    }

    -- Icon (non-interactive, just display)
    local icon_widget = create_image_button({
        image_path = app.icon,
        fallback_text = "◫",
        image_size = dpi(24),
        padding = dpi(2),
        bg_color = "transparent",
        border_color = "transparent",
        hover_bg = "transparent",
    })

    -- Pin button
    entry.pin_button = create_image_button({
        image_path = entry.is_pinned and CONFIG.icons.pinned or CONFIG.icons.pin,
        image_size = dpi(16),
        padding = dpi(8),
        opacity = 0.6,
        opacity_hover = 1.0,
        bg_color = theme.appmenu.pin_button_bg,
        hover_bg = theme.appmenu.pin_button_bg_focus,
        border_color = theme.appmenu.button_border .. "55",
        hover_border = theme.appmenu.button_border_focus,
        on_click = function()
            self:_toggle_pin(app)
            return true
        end,
    })
    entry.pin_button.visible = false

    entry.pin_button:connect_signal("mouse::enter", function()
        self._menu.focus.pin_focused = true
        self._menu.focus.info_focused = false
        self:_emit_focus_update()
    end)
    entry.pin_button:connect_signal("mouse::leave", function()
        self._menu.focus.pin_focused = false
        self:_emit_focus_update()
    end)

    -- Info button
    entry.info_button = create_image_button({
        image_path = CONFIG.icons.info,
        fallback_text = "ⓘ",
        image_size = dpi(16),
        padding = dpi(8),
        opacity = 0.6,
        opacity_hover = 1.0,
        bg_color = theme.appmenu.pin_button_bg,
        hover_bg = theme.appmenu.pin_button_bg_focus,
        border_color = theme.appmenu.button_border .. "55",
        hover_border = theme.appmenu.button_border_focus,
        on_click = function()
            self:_show_desktop_info(app.desktop_path)
            self:hide()
            return true
        end,
    })
    entry.info_button.visible = false

    entry.info_button:connect_signal("mouse::enter", function()
        self._menu.focus.info_focused = true
        self._menu.focus.pin_focused = false
        self:_emit_focus_update()
    end)
    entry.info_button:connect_signal("mouse::leave", function()
        self._menu.focus.info_focused = false
        self:_emit_focus_update()
    end)

    -- Main background/row
    entry.background = wibox.widget {
        {
            {
                {
                    icon_widget,
                    {
                        text = app.name,
                        widget = wibox.widget.textbox,
                        font = beautiful.font or "Sans 11",
                    },
                    spacing = dpi(8),
                    layout = wibox.layout.fixed.horizontal,
                },
                nil,
                {
                    entry.pin_button,
                    entry.info_button,
                    spacing = dpi(4),
                    layout = wibox.layout.fixed.horizontal,
                },
                layout = wibox.layout.align.horizontal,
            },
            margins = dpi(6),
            widget = wibox.container.margin,
        },
        bg = theme.appmenu.button_bg,
        fg = theme.appmenu.fg,
        shape = function(cr, w, h) gears.shape.rounded_rect(cr, w, h, 6) end,
        shape_border_width = dpi(1),
        shape_border_color = theme.appmenu.button_border .. "33",
        forced_height = dpi(44),
        widget = wibox.container.background,
    }

    -- Focus update function
    function entry:update_menu_focus(menu)
        local focus = menu._menu.focus
        local is_focused = focus.type == "apps" and focus.index == index

        self.pin_button.visible = is_focused
        self.info_button.visible = is_focused

        if is_focused then
            if focus.pin_focused then
                self.background.bg = theme.appmenu.button_bg
                self.background.fg = theme.appmenu.fg
                self.background.shape_border_color = theme.appmenu.button_border_focus
                self.pin_button:emit_signal("button::focus")
                self.info_button:emit_signal("button::unfocus")
            elseif focus.info_focused then
                self.background.bg = theme.appmenu.button_bg
                self.background.fg = theme.appmenu.fg
                self.background.shape_border_color = theme.appmenu.button_border_focus
                self.pin_button:emit_signal("button::unfocus")
                self.info_button:emit_signal("button::focus")
            else
                self.background.bg = menu._menu.control_pressed
                    and theme.appmenu.button_bg_sudo
                    or theme.appmenu.button_bg_focus
                self.background.fg = beautiful.fg_focus
                self.background.shape_border_color = menu._menu.control_pressed
                    and theme.appmenu.button_border_sudo
                    or theme.appmenu.button_border_focus
                self.pin_button:emit_signal("button::unfocus")
                self.info_button:emit_signal("button::unfocus")
            end
        else
            self.background.bg = theme.appmenu.button_bg
            self.background.fg = theme.appmenu.fg
            self.background.shape_border_color = theme.appmenu.button_border .. "33"
        end
    end

    -- Mouse enter changes focus
    entry.background:connect_signal("mouse::enter", function()
        self._menu.focus = {
            type = "apps",
            index = index,
            pin_focused = false,
            info_focused = false
        }
        self:_emit_focus_update()
    end)

    -- Click handlers
    entry.background:buttons(gears.table.join(
        awful.button({}, 1, function()
            if not self._menu.focus.pin_focused and not self._menu.focus.info_focused then
                awful.spawn(app.exec)
                self:hide()
            end
        end),
        awful.button({"Control"}, 1, function()
            if not self._menu.focus.pin_focused and not self._menu.focus.info_focused then
                self:_run_with_sudo(app.exec)
                self:hide()
            end
        end)
    ))

    add_hover_cursor(entry.background)
    add_hover_cursor(entry.pin_button)
    add_hover_cursor(entry.info_button)

    -- Container with margins
    entry.container = wibox.widget {
        entry.background,
        left = dpi(8),
        right = dpi(8),
        widget = wibox.container.margin,
    }

    return entry
end

--------------------------------------------------------------------------------
-- Focus Management
--------------------------------------------------------------------------------

function app_menu:_emit_focus_update()
    -- Update pinned widgets
    for i, widget in pairs(self._menu.pinned_widgets) do
        if widget.update_menu_focus then
            widget:update_menu_focus(self)
        end
    end

    -- Update app widgets
    for i, entry in pairs(self._menu.app_widgets) do
        if entry.update_menu_focus then
            entry:update_menu_focus(self)
        end
    end
end

function app_menu:_handle_navigation(mod, key)
    local focus = self._menu.focus
    local is_ctrl = false
    for _, m in ipairs(mod) do
        if m == "Control" then
            is_ctrl = true
            break
        end
    end
    
    if not focus.index then
        focus.type = "apps"
        focus.index = 1
    end
    
    if key == "Up" then
        if focus.type == "apps" then
            if focus.index == 1 and #self._menu.pinned_apps > 0 then
                focus.type = "pinned"
                focus.index = 1
                focus.pin_focused = false
                focus.info_focused = false
            else
                focus.index = math.max(1, focus.index - 1)
                focus.pin_focused = false
                focus.info_focused = false
                self:_ensure_focused_visible()
            end
        end
        
    elseif key == "Down" then
        if focus.type == "pinned" then
            focus.type = "apps"
            focus.index = 1
            focus.pin_focused = false
            focus.info_focused = false
            self:_ensure_focused_visible()
        elseif focus.type == "apps" and focus.index < #self._menu.filtered_list then
            focus.index = focus.index + 1
            focus.pin_focused = false
            focus.info_focused = false
            self:_ensure_focused_visible()
        end
        
    elseif key == "Left" then
        if focus.type == "pinned" then
            if is_ctrl then
                self:_reorder_pinned(focus.index, -1)
                return
            elseif focus.index > 1 then
                focus.index = focus.index - 1
            end
        elseif focus.type == "apps" then
            if focus.info_focused then
                focus.info_focused = false
                focus.pin_focused = true
            elseif focus.pin_focused then
                focus.pin_focused = false
            end
        end
        
    elseif key == "Right" then
        if focus.type == "pinned" then
            if is_ctrl then
                self:_reorder_pinned(focus.index, 1)
                return
            elseif focus.index < #self._menu.pinned_apps then
                focus.index = focus.index + 1
            end
        elseif focus.type == "apps" then
            if not focus.pin_focused and not focus.info_focused then
                focus.pin_focused = true
            elseif focus.pin_focused then
                focus.pin_focused = false
                focus.info_focused = true
            end
        end

    elseif key == "Tab" and focus.type == "pinned" then
        focus.index = focus.index < #self._menu.pinned_apps
            and focus.index + 1
            or 1
        
    elseif key == "Return" then
        if focus.type == "apps" then
            local app = self._menu.filtered_list[focus.index]
            if app then
                if focus.pin_focused then
                    self:_toggle_pin(app)
                elseif focus.info_focused then
                    self:_show_desktop_info(app.desktop_path)
                else
                    if is_ctrl then
                        self:_run_with_sudo(app.exec)
                    else
                        awful.spawn(app.exec)
                    end
                    self:hide()
                end
            end
        elseif focus.type == "pinned" then
            local app = self._menu.pinned_apps[focus.index]
            if app then
                if is_ctrl then
                    self:_run_with_sudo(app.exec)
                else
                    awful.spawn(app.exec)
                end
                self:hide()
            end
        end

    elseif key == "Home" then
        focus.index = 1
        focus.pin_focused = false
        focus.info_focused = false
        if focus.type == "apps" then
            self:_ensure_focused_visible()
        end

    elseif key == "End" then
        if focus.type == "apps" then
            focus.index = #self._menu.filtered_list
            focus.pin_focused = false
            focus.info_focused = false
            self:_ensure_focused_visible()
        elseif focus.type == "pinned" then
            focus.index = #self._menu.pinned_apps
        end
    end

    self:_emit_focus_update()
end

--------------------------------------------------------------------------------
-- Scrolling
--------------------------------------------------------------------------------

function app_menu:_scroll_list(direction)
    if direction > 0 then  -- Down
        if self._menu.current_start + CONFIG.visible_entries <= #self._menu.filtered_list then
            self._menu.current_start = self._menu.current_start + 1
            if self._menu.focus.type == "apps" then
                self._menu.focus.index = self._menu.focus.index + 1
            end
            self:refresh()
        end
    else  -- Up
        if self._menu.current_start > 1 then
            self._menu.current_start = self._menu.current_start - 1
            if self._menu.focus.type == "apps" then
                self._menu.focus.index = self._menu.focus.index - 1
            end
            self:refresh()
        end
    end
end

function app_menu:_ensure_focused_visible()
    if self._menu.focus.type ~= "apps" or not self._menu.focus.index then
        return
    end

    local index = self._menu.focus.index

    if index < self._menu.current_start then
        self._menu.current_start = index
        self:refresh()
    elseif index >= self._menu.current_start + CONFIG.visible_entries then
        self._menu.current_start = index - CONFIG.visible_entries + 1
        self:refresh()
    end
end

--------------------------------------------------------------------------------
-- Desktop Files
--------------------------------------------------------------------------------

function app_menu:_scan_desktop_files()
    local paths = {
        "/usr/share/applications/",
        os.getenv("HOME") .. "/.local/share/applications/",
        os.getenv("HOME") .. "/.local/share/flatpak/exports/share/applications/",
        "/var/lib/flatpak/exports/share/applications/",
    }

    self._menu.desktop_entries = {}

    for _, path in ipairs(paths) do
        local handle = io.popen('find "' .. path .. '" -name "*.desktop" 2>/dev/null')
        if handle then
            for file in handle:lines() do
                local f = io.open(file)
                if f then
                    local content = f:read("*all")
                    f:close()

                    local name = content:match("Name=([^\n]+)")
                    local exec = content:match("Exec=([^\n]+)")
                    local nodisplay = content:match("NoDisplay=([^\n]+)")
                    local hidden = content:match("Hidden=([^\n]+)")

                    if name and exec and nodisplay ~= "true" and hidden ~= "true" then
                        exec = self:_process_exec_command(exec, file)
                        if exec then
                            table.insert(self._menu.desktop_entries, {
                                name = name,
                                exec = exec,
                                icon = self:_get_icon_path(content),
                                desktop_path = file,
                            })
                        end
                    end
                end
            end
            handle:close()
        end
    end

    table.sort(self._menu.desktop_entries, function(a, b)
        return string.lower(a.name) < string.lower(b.name)
    end)

    -- Initialize filtered list
    self:_update_filtered_list("")
end

function app_menu:_process_exec_command(exec, desktop_file_path)
    if not exec then return nil end

    -- Handle escaped quotes
    exec = exec:gsub('\\"([^"]+)\\"', function(path)
        return path:gsub(" ", "\\ ")
    end)
    exec = exec:gsub('\\"', '"'):gsub("\\'", "'")

    -- Remove field codes
    exec = exec:gsub("%%[fFuU]", "")
    exec = exec:gsub("%%k", desktop_file_path)
    exec = exec:gsub("%%[A-Z]", "")

    return exec
end

function app_menu:_get_icon_path(desktop_file_content)
    local icon_name = desktop_file_content:match("Icon=([^\n]+)")
    if not icon_name then return nil end
    
    -- Absolute path
    if icon_name:match("^/") then
        local f = io.open(icon_name)
        if f then
            f:close()
            return icon_name
        end
    end

    -- Search common icon directories
    local icon_dirs = {
        "/usr/share/icons/hicolor/scalable/apps/",
        "/usr/share/icons/hicolor/256x256/apps/",
        "/usr/share/icons/hicolor/64x64/apps/",
        "/usr/share/icons/hicolor/48x48/apps/",
        "/usr/share/icons/hicolor/16x16/apps/",
        "/usr/share/icons/",
        "/usr/share/pixmaps/",
        os.getenv("HOME") .. "/.local/share/icons/hicolor/48x48/apps/",
        os.getenv("HOME") .. "/.local/share/icons/hicolor/scalable/apps/",
    }
    local extensions = { ".png", ".svg", ".xpm", "" }

    for _, dir in ipairs(icon_dirs) do
        for _, ext in ipairs(extensions) do
            local icon_path = dir .. icon_name .. ext
            local f = io.open(icon_path)
            if f then
                f:close()
                return icon_path
            end
        end
    end

    return nil
end

function app_menu:_update_filtered_list(search_term)
    self._menu.filtered_list = {}
    search_term = string.lower(search_term or "")

    for _, app in ipairs(self._menu.desktop_entries) do
        if string.find(string.lower(app.name), search_term, 1, true) then
            table.insert(self._menu.filtered_list, app)
        end
    end
end

--------------------------------------------------------------------------------
-- Pinned Apps
--------------------------------------------------------------------------------

function app_menu:_load_pinned_apps()
    local success, apps = pcall(dofile, config_dir .. "persistent/pinned_apps.lua")
    if success and apps and type(apps) == "table" then
        for _, app in ipairs(apps) do
            if app.exec then
                app.exec = self:_process_exec_command(app.exec, "")
            end
        end
        self._menu.pinned_apps = apps
    else
        self._menu.pinned_apps = {}
    end
end

function app_menu:_save_pinned_apps()
    local file = io.open(config_dir .. "persistent/pinned_apps.lua", "w")
    if file then
        file:write("return {")
        for _, app in ipairs(self._menu.pinned_apps) do
            file:write(string.format(
                '\n  {name = %s, exec = %s, icon = %s},',
                escape_string(app.name),
                escape_string(app.exec),
                escape_string(app.icon or "")
            ))
        end
        file:write("\n}")
        file:close()
    end
end

function app_menu:_is_app_pinned(app)
    for _, pinned in ipairs(self._menu.pinned_apps) do
        if pinned.name == app.name then
            return true
        end
    end
    return false
end

function app_menu:_toggle_pin(app)
    if not app then return end

    -- Check if already pinned
    for i, pinned_app in ipairs(self._menu.pinned_apps) do
        if pinned_app.name == app.name then
            table.remove(self._menu.pinned_apps, i)
            self:_save_pinned_apps()
            self:refresh()
            return
        end
    end

    -- Add to pinned apps
    if #self._menu.pinned_apps < CONFIG.max_pinned then
        table.insert(self._menu.pinned_apps, {
            name = app.name,
            exec = app.exec,
            icon = app.icon,
        })
        self:_save_pinned_apps()
        self:refresh()
    end
end

function app_menu:_remove_pinned(index)
    table.remove(self._menu.pinned_apps, index)
    self:_save_pinned_apps()
    self:refresh()
end

function app_menu:_reorder_pinned(index, direction)
    local new_index = index + direction
    if new_index < 1 or new_index > #self._menu.pinned_apps then
        return
    end

    self._menu.pinned_apps[index], self._menu.pinned_apps[new_index] =
        self._menu.pinned_apps[new_index], self._menu.pinned_apps[index]

    self._menu.focus.index = new_index
    self:_save_pinned_apps()
    self:refresh()
end

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------

function app_menu:_run_with_sudo(command)
    awful.spawn.with_shell(string.format("zenity --password | sudo -S %s", command))
end

function app_menu:_show_desktop_info(desktop_path)
    if not desktop_path then return end
    local escaped_path = desktop_path:gsub('"', '\\"')
    awful.spawn.with_shell(string.format(
        'zenity --info --title="Desktop File Location" --text="<b>Desktop File Path:</b>\\n%s\\n\\nClick to select and Ctrl+C to copy" --width=500',
        escaped_path
    ))
end

--------------------------------------------------------------------------------
-- Module Interface (backwards compatible)
--------------------------------------------------------------------------------

local appmenu_instance = nil

local function appmenu_init()
    appmenu_instance = app_menu.new()
    appmenu_instance:init()
    return appmenu_instance:get_popup()
end

local function appmenu_show()
    if appmenu_instance then
        appmenu_instance:show()
    end
end

local function appmenu_hide()
    if appmenu_instance then
        appmenu_instance:hide()
    end
end

local function appmenu_toggle()
    if appmenu_instance then
        appmenu_instance:toggle()
    end
end

-- Also expose scan function for compatibility
local function scan_desktop_files()
    if appmenu_instance then
        appmenu_instance:_scan_desktop_files()
    end
end

return {
    init = appmenu_init,
    show = appmenu_show,
    hide = appmenu_hide,
    toggle = appmenu_toggle,
    scan_desktop_files = scan_desktop_files,

    -- Export class for direct use
    app_menu = app_menu,
}