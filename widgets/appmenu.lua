-- Application Menu
local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local wibox = require("wibox")
local dpi = require("beautiful.xresources").apply_dpi
local naughty = require("naughty")

local config_dir = gears.filesystem.get_configuration_dir()
local icon_dir = config_dir .. "theme-icons/"
local theme = load_util("theme")
local create_text_input = load_widget("text_input")

do
    local in_error = false
    awesome.connect_signal("debug::error", function (err)
        -- Make sure we don't go into an endless error loop
        if in_error then return end
        in_error = true

        debug_log("[Error]: " .. tostring(err))
        in_error = false
    end)
end

-- Core menu state
appmenu_data = {
    wibox = nil,
    search_input = nil,
    visible_entries = 10,
    current_start = 1,
    desktop_entries = {},
    filtered_list = {},
    pinned_apps = {},
    max_pinned = 8,
    font = font_with_size(13),
    current_focus = {
        type = "pinned",  -- "pinned" or "apps"
        index = nil,
        pin_focused = false,  -- Whether pin button is focused (for apps only)
        info_focused = false  -- Whether info button is focused (for apps only)
    },
    icons = {
        search = icon_dir .. "search.png",
        pin = icon_dir .. "pin.svg",
        pinned = icon_dir .. "unpin.png",
        info = icon_dir .. "folder.png"
    },
    control_pressed = false
}

local function handle_exec_quotes(str)
    if not str then return nil end
    str = str:gsub('\\"([^"]+)\\"', function(path)
        return path:gsub(" ", "\\ ")
    end)
    str = str:gsub('\\"', '"'):gsub("\\'", "'")
    return str
end

local function process_exec_command(exec, desktop_file_path)
    if not exec then return nil end
    exec = handle_exec_quotes(exec)
    exec = exec:gsub("%%[fFuU]", "")
    exec = exec:gsub("%%k", desktop_file_path)
    exec = exec:gsub("%%[A-Z]", "")
    return exec
end

local function get_icon_path(desktop_file_content)
    local icon_name = desktop_file_content:match("Icon=([^\n]+)")
    if not icon_name then return nil end
    
    -- Check if it's an absolute path
    if icon_name:match("^/") then
        local f = io.open(icon_name)
        if f then
            f:close()
            return icon_name
        end
    end
    
    -- Search common icon directories
    local icon_dir = "/usr/share/icons/"
    local icon_paths = {
        icon_dir .. "hicolor/scalable/apps/",
        icon_dir .. "hicolor/256x256/apps/",
        icon_dir .. "hicolor/64x64/apps/",
        icon_dir .. "hicolor/48x48/apps/",
        icon_dir .. "hicolor/16x16/apps/",
        icon_dir,
        "/usr/share/pixmaps/",
        os.getenv("HOME") .. "/.local/share/icons/hicolor/48x48/apps/",
        os.getenv("HOME") .. "/.local/share/icons/hicolor/scalable/apps/"
    }
    local extensions = { ".png", ".svg", ".xpm", "" }
    
    for _, path in ipairs(icon_paths) do
        for _, ext in ipairs(extensions) do
            local icon_path = path .. icon_name .. ext
            local f = io.open(icon_path)
            if f then
                f:close()
                return icon_path
            end
        end
    end
    
    return nil
end

function scan_desktop_files()
    local paths = {
        "/usr/share/applications/",
        os.getenv("HOME") .. "/.local/share/applications/",
        os.getenv("HOME") .. "/.local/share/flatpak/exports/share/applications/",
        "/var/lib/flatpak/exports/share/applications/"
    }
    
    appmenu_data.desktop_entries = {}
    
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
                        exec = process_exec_command(exec, file)
                        if exec then
                            table.insert(appmenu_data.desktop_entries, {
                                name = name,
                                exec = exec,
                                icon = get_icon_path(content),
                                desktop_path = file
                            })
                        end
                    end
                end
            end
            handle:close()
        end
    end
    
    table.sort(appmenu_data.desktop_entries, function(a, b)
        return string.lower(a.name) < string.lower(b.name)
    end)
end

function save_pinned_apps()
    local file = io.open(config_dir .. "persistent/pinned_apps.lua", "w")
    if file then
        file:write("return {")
        for _, app in ipairs(appmenu_data.pinned_apps) do
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

function load_pinned_apps()
    local success, apps = pcall(dofile, config_dir .. "persistent/pinned_apps.lua")
    if success and apps and type(apps) == "table" then
        for _, app in ipairs(apps) do
            if app.exec then
                app.exec = handle_exec_quotes(app.exec)
            end
        end
        appmenu_data.pinned_apps = apps
    end
end

function toggle_pin(app)
    if not app then return end
    
    -- Check if already pinned
    for i, pinned_app in ipairs(appmenu_data.pinned_apps) do
        if pinned_app.name == app.name then
            table.remove(appmenu_data.pinned_apps, i)
            save_pinned_apps()
            refresh_menu_widget()
            return
        end
    end
    
    -- Add to pinned apps
    if #appmenu_data.pinned_apps < appmenu_data.max_pinned then
        table.insert(appmenu_data.pinned_apps, {
            name = app.name,
            exec = app.exec,
            icon = app.icon
        })
        save_pinned_apps()
        refresh_menu_widget()
    else
        --[[ naughty.notify({
            text = "Maximum number of pinned apps reached",
            timeout = 2
        }) ]]
    end
end

local function reorder_pinned(index, direction)
    local new_index = index + direction
    if new_index < 1 or new_index > #appmenu_data.pinned_apps then
        return
    end
    
    appmenu_data.pinned_apps[index], appmenu_data.pinned_apps[new_index] =
        appmenu_data.pinned_apps[new_index], appmenu_data.pinned_apps[index]

    appmenu_data.current_focus.index = new_index
    save_pinned_apps()
    refresh_menu_widget()
end

local function create_pinned_icon(app, index)
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
            awful.spawn(app.exec)
            appmenu_hide()
            return true
        end,
        on_right_click = function()
            table.remove(appmenu_data.pinned_apps, index)
            save_pinned_apps()
            refresh_menu_widget()
        end
    })

    function icon_widget:update_focus()
        if appmenu_data.current_focus.type == "pinned" and
           appmenu_data.current_focus.index == index then
            self:emit_signal("button::focus")
            if appmenu_data.control_pressed then
                gears.timer.start_new(0.01, function()
                    self.shape_border_color = theme.appmenu.button_border_sudo
                    self.bg = theme.appmenu.button_bg_sudo
                end)
            end
        else
            self:emit_signal("button::unfocus")
        end
    end

    appmenu_data.wibox:connect_signal("property::current_focus", function()
        icon_widget:update_focus()
    end)

    icon_widget:connect_signal("mouse::enter", function()
        appmenu_data.current_focus = { type = "pinned", index = index, pin_focused = false }
        appmenu_data.wibox:emit_signal("property::current_focus")
    end)

    add_hover_cursor(icon_widget)
    icon_widget:update_focus()

    return icon_widget
end

local function create_app_entry(app, index)
    local widget = { is_pinned = false }
    
    -- Check if pinned
    for _, pinned_app in ipairs(appmenu_data.pinned_apps) do
        if pinned_app.name == app.name then
            widget.is_pinned = true
            break
        end
    end

    -- Icon
    local icon_widget = create_image_button({
        image_path = app.icon,
        fallback_text = "◫",
        image_size = dpi(24),
        padding = dpi(2),
        bg_color = "transparent",
        border_color = "transparent",
        hover_bg = "transparent"
    })

    -- Pin button
    widget.pin_button = create_image_button({
        image_path = widget.is_pinned and appmenu_data.icons.pinned or appmenu_data.icons.pin,
        image_size = dpi(16),
        padding = dpi(8),
        opacity = 0.6,
        opacity_hover = 1.0,
        bg_color = theme.appmenu.pin_button_bg,
        hover_bg = theme.appmenu.pin_button_bg_focus,
        border_color = theme.appmenu.button_border .. "55",
        hover_border = theme.appmenu.button_border_focus,
        on_click = function()
            toggle_pin(app)
            return true
        end
    })
    widget.pin_button.visible = false

    widget.pin_button:connect_signal("mouse::enter", function()
        appmenu_data.current_focus.pin_focused = true
        appmenu_data.wibox:emit_signal("property::current_focus")
    end)
    widget.pin_button:connect_signal("mouse::leave", function()
        appmenu_data.current_focus.pin_focused = false
        appmenu_data.wibox:emit_signal("property::current_focus")
    end)

    -- Info button
    widget.info_button = create_image_button({
        image_path = appmenu_data.icons.info,
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
            show_desktop_info(app.desktop_path)
            appmenu_hide()
            return true
        end
    })
    widget.info_button.visible = false

    widget.info_button:connect_signal("mouse::enter", function()
        appmenu_data.current_focus.info_focused = true
        appmenu_data.wibox:emit_signal("property::current_focus")
    end)
    widget.info_button:connect_signal("mouse::leave", function()
        appmenu_data.current_focus.info_focused = false
        appmenu_data.wibox:emit_signal("property::current_focus")
    end)

    -- Main content
    widget.background = wibox.widget {
        {
            {
                {
                    icon_widget,
                    {
                        text = app.name,
                        widget = wibox.widget.textbox,
                        font = beautiful.font or "Sans 11"
                    },
                    spacing = dpi(8),
                    layout = wibox.layout.fixed.horizontal,
                },
                nil,
                {
                    widget.pin_button,
                    widget.info_button,
                    spacing = dpi(4),
                    layout = wibox.layout.fixed.horizontal,
                },
                layout = wibox.layout.align.horizontal
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

    function widget:update_focus()
        local is_focused = appmenu_data.current_focus.type == "apps" and
                          appmenu_data.current_focus.index == index

        self.pin_button.visible = is_focused
        self.info_button.visible = is_focused

        if is_focused then
            if appmenu_data.current_focus.pin_focused then
                self.background.bg = theme.appmenu.button_bg
                self.background.fg = theme.appmenu.fg
                self.background.shape_border_color = theme.appmenu.button_border_focus
                self.pin_button:emit_signal("button::focus")
                self.info_button:emit_signal("button::unfocus")
            elseif appmenu_data.current_focus.info_focused then
                self.background.bg = theme.appmenu.button_bg
                self.background.fg = theme.appmenu.fg
                self.background.shape_border_color = theme.appmenu.button_border_focus
                self.pin_button:emit_signal("button::unfocus")
                self.info_button:emit_signal("button::focus")
            else
                self.background.bg = appmenu_data.control_pressed and
                    theme.appmenu.button_bg_sudo or theme.appmenu.button_bg_focus
                self.background.fg = beautiful.fg_focus
                self.background.shape_border_color = appmenu_data.control_pressed and
                    theme.appmenu.button_border_sudo or theme.appmenu.button_border_focus
                self.pin_button:emit_signal("button::unfocus")
                self.info_button:emit_signal("button::unfocus")
            end
        else
            self.background.bg = theme.appmenu.button_bg
            self.background.fg = theme.appmenu.fg
            self.background.shape_border_color = theme.appmenu.button_border .. "33"
        end
    end

    appmenu_data.wibox:connect_signal("property::current_focus", function()
        widget:update_focus()
    end)

    widget.background:connect_signal("mouse::enter", function()
        appmenu_data.current_focus = { type = "apps", index = index, pin_focused = false, info_focused = false }
        appmenu_data.wibox:emit_signal("property::current_focus")
    end)

    widget.background:buttons(gears.table.join(
        awful.button({}, 1, function()
            if not appmenu_data.current_focus.pin_focused and not appmenu_data.current_focus.info_focused then
                awful.spawn(app.exec)
                appmenu_hide()
            end
        end),
        awful.button({"Control"}, 1, function()
            if not appmenu_data.current_focus.pin_focused and not appmenu_data.current_focus.info_focused then
                run_with_sudo(app.exec)
                appmenu_hide()
            end
        end)
    ))

    add_hover_cursor(widget.background)
    add_hover_cursor(widget.pin_button)
    add_hover_cursor(widget.info_button)
    widget:update_focus()

    return wibox.widget {
        widget.background,
        left = dpi(8),
        right = dpi(8),
        widget = wibox.container.margin
    }
end

local function create_pinned_row()
    local row = wibox.widget {
        layout = wibox.layout.fixed.horizontal,
        spacing = dpi(8),
    }

    for i, app in ipairs(appmenu_data.pinned_apps) do
        row:add(create_pinned_icon(app, i))
    end

    return wibox.widget {
        {
            {
                row,
                margins = dpi(8),
                widget = wibox.container.margin
            },
            bg = theme.appmenu.bg,
            widget = wibox.container.background
        },
        visible = #appmenu_data.pinned_apps > 0,
        layout = wibox.layout.fixed.horizontal
    }
end

local function create_app_list()
    local list = wibox.widget {
        layout = wibox.layout.fixed.vertical,
        spacing = dpi(6),
    }

    local start_idx = appmenu_data.current_start
    local end_idx = math.min(start_idx + appmenu_data.visible_entries - 1, #appmenu_data.filtered_list)

    for i = start_idx, end_idx do
        local app = appmenu_data.filtered_list[i]
        if app then
            list:add(create_app_entry(app, i))
        end
    end

    return list
end

local function create_search_box()
    local search_icon = wibox.widget {
        {
            image = appmenu_data.icons.search,
            resize = true,
            forced_width = dpi(18),
            forced_height = dpi(18),
            opacity = 0.5,
            widget = wibox.widget.imagebox
        },
        valign = 'center',
        widget = wibox.container.place
    }

    local search_content = wibox.widget {
        search_icon,
        {
            appmenu_data.search_input.background,
            bottom = dpi(4),
            widget = wibox.container.margin
        },
        spacing = dpi(8),
        layout = wibox.layout.fixed.horizontal
    }

    local search_container = wibox.widget {
        {
            search_content,
            margins = dpi(12),
            widget = wibox.container.margin
        },
        bg = theme.appmenu.bg,
        shape = function(cr, w, h) gears.shape.rounded_rect(cr, w, h, dpi(15)) end,
        shape_border_width = dpi(1),
        shape_border_color = theme.appmenu.button_border .. "33",
        widget = wibox.container.background
    }

    local separator = wibox.widget {
        widget = wibox.widget.separator,
        orientation = "horizontal",
        forced_height = 1,
        color = theme.appmenu.button_border .. "33",
        span_ratio = 0.98
    }

    return wibox.widget {
        -- Pinned apps section
        {
            {
                {
                    create_pinned_row(),
                    margins = dpi(8),
                    widget = wibox.container.margin
                },
                separator,
                layout = wibox.layout.fixed.vertical,
                spacing = dpi(1)
            },
            bg = theme.appmenu.bg,
            visible = #appmenu_data.pinned_apps > 0,
            widget = wibox.container.background
        },
        -- Search box
        {
            search_container,
            left = dpi(12),
            right = dpi(12),
            top = dpi(10),
            bottom = dpi(10),
            widget = wibox.container.margin
        },
        -- App list
        {
            create_app_list(),
            margins = dpi(4),
            widget = wibox.container.margin
        },
        layout = wibox.layout.fixed.vertical,
        spacing = dpi(4)
    }
end

function update_filtered_list(search_term)
    appmenu_data.filtered_list = {}
    search_term = string.lower(search_term or "")
    
    for _, app in ipairs(appmenu_data.desktop_entries) do
        if string.find(string.lower(app.name), search_term, 1, true) then
            table.insert(appmenu_data.filtered_list, app)
        end
    end
end

function refresh_menu_widget()
    if not appmenu_data.wibox then return end

    local new_height = #appmenu_data.pinned_apps > 0 and dpi(672) or dpi(590)
    appmenu_data.wibox.maximum_height = new_height
    appmenu_data.wibox.minimum_height = new_height
    appmenu_data.wibox.widget = wibox.container.constraint(
        create_search_box(), "exact", dpi(500), new_height
    )
end

local function scroll_list(direction)
    if direction > 0 then  -- Down
        if appmenu_data.current_start + appmenu_data.visible_entries <= #appmenu_data.filtered_list then
            appmenu_data.current_start = appmenu_data.current_start + 1
            if appmenu_data.current_focus.type == "apps" then
                appmenu_data.current_focus.index = appmenu_data.current_focus.index + 1
            end
            refresh_menu_widget()
        end
    else  -- Up
        if appmenu_data.current_start > 1 then
            appmenu_data.current_start = appmenu_data.current_start - 1
            local max_visible = appmenu_data.current_start + appmenu_data.visible_entries - 1
            if appmenu_data.current_focus.type == "apps" then
                appmenu_data.current_focus.index = appmenu_data.current_focus.index - 1
            end
            refresh_menu_widget()
        end
    end
end

local function ensure_focused_visible()
    if appmenu_data.current_focus.type ~= "apps" or not appmenu_data.current_focus.index then
        return
    end
    
    local index = appmenu_data.current_focus.index
    
    if index < appmenu_data.current_start then
        appmenu_data.current_start = index
        refresh_menu_widget()
    elseif index >= appmenu_data.current_start + appmenu_data.visible_entries then
        appmenu_data.current_start = index - appmenu_data.visible_entries + 1
        refresh_menu_widget()
    end
end

local function handle_keyboard_navigation(mod, key)
    local focus = appmenu_data.current_focus
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
            if focus.index == 1 and #appmenu_data.pinned_apps > 0 then
                focus.type = "pinned"
                focus.index = 1
                focus.pin_focused = false
                focus.info_focused = false
            else
                focus.index = math.max(1, focus.index - 1)
                focus.pin_focused = false
                focus.info_focused = false
                ensure_focused_visible()
            end
        end
        
    elseif key == "Down" then
        if focus.type == "pinned" then
            focus.type = "apps"
            focus.index = 1
            focus.pin_focused = false
            focus.info_focused = false
            ensure_focused_visible()
        elseif focus.type == "apps" and focus.index < #appmenu_data.filtered_list then
            focus.index = focus.index + 1
            focus.pin_focused = false
            focus.info_focused = false
            ensure_focused_visible()
        end
        
    elseif key == "Left" then
        if focus.type == "pinned" then
            if is_ctrl then
                reorder_pinned(focus.index, -1)
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
                reorder_pinned(focus.index, 1)
                return
            elseif focus.index < #appmenu_data.pinned_apps then
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
        focus.index = focus.index < #appmenu_data.pinned_apps and focus.index + 1 or 1
        
    elseif key == "Return" then
        if focus.type == "apps" then
            local app = appmenu_data.filtered_list[focus.index]
            if app then
                if focus.pin_focused then
                    toggle_pin(app)
                elseif focus.info_focused then
                    show_desktop_info(app.desktop_path)
                else
                    if is_ctrl then
                        run_with_sudo(app.exec)
                    else
                        awful.spawn(app.exec)
                    end
                    appmenu_hide()
                end
            end
        elseif focus.type == "pinned" then
            local app = appmenu_data.pinned_apps[focus.index]
            if app then
                if is_ctrl then
                    run_with_sudo(app.exec)
                else
                    awful.spawn(app.exec)
                end
                appmenu_hide()
            end
        end

    elseif key == "Home" then
        focus.index = 1
        focus.pin_focused = false
        focus.info_focused = false
        if focus.type == "apps" then
            ensure_focused_visible()
        end

    elseif key == "End" then
        if focus.type == "apps" then
            focus.index = #appmenu_data.filtered_list
            focus.pin_focused = false
            focus.info_focused = false
            ensure_focused_visible()
        elseif focus.type == "pinned" then
            focus.index = #appmenu_data.pinned_apps
        end
    end
    
    appmenu_data.wibox:emit_signal("property::current_focus")
end

function run_with_sudo(command)
    awful.spawn.with_shell(string.format("zenity --password | sudo -S %s", command))
end

function show_desktop_info(desktop_path)
    if not desktop_path then return end
    -- Escape the path for shell
    local escaped_path = desktop_path:gsub('"', '\\"')
    -- Use zenity to show the path with copy-able text
    awful.spawn.with_shell(string.format(
        'zenity --info --title="Desktop File Location" --text="<b>Desktop File Path:</b>\\n%s\\n\\nClick to select and Ctrl+C to copy" --width=500',
        escaped_path
    ))
end

function appmenu_create()
    if #appmenu_data.desktop_entries == 0 then
        scan_desktop_files()
    end

    appmenu_data.search_input = create_text_input({
        disable_arrows = true,
        font = appmenu_data.font,
        height = dpi(24),
        on_text_change = function(new_text)
            appmenu_data.current_start = 1
            appmenu_data.current_focus = { type = "apps", index = 1, pin_focused = false, info_focused = false }
            update_filtered_list(new_text)
            ensure_focused_visible()
            refresh_menu_widget()
        end
    })

    update_filtered_list("")
    return create_search_box()
end

function appmenu_init()
    load_pinned_apps()

    appmenu_data.wibox = awful.popup{
        screen = mouse.screen,
        widget = wibox.widget.base.make_widget(),
        bg = theme.appmenu.bg,
        border_color = theme.appmenu.border,
        border_width = dpi(1),
        visible = false,
        ontop = true,
        placement = awful.placement.centered,
        shape = function(cr, w, h) gears.shape.rounded_rect(cr, w, h, dpi(16)) end,
        maximum_width = dpi(500),
        maximum_height = dpi(672),
        minimum_width = dpi(500),
        minimum_height = dpi(672)
    }

    appmenu_data.wibox.widget = wibox.container.constraint(
        appmenu_create(), "exact", dpi(500), dpi(672)
    )

    appmenu_data.wibox:buttons(gears.table.join(
        awful.button({}, 4, function() scroll_list(-1) end),
        awful.button({}, 5, function() scroll_list(1) end)
    ))

    appmenu_data.keygrabber = awful.keygrabber {
        autostart = false,
        keypressed_callback = function(self, mod, key)
            if key == "Control_L" or key == "Control_R" then
                appmenu_data.control_pressed = true
                appmenu_data.wibox:emit_signal("property::current_focus")
                return
            end

            if not appmenu_data.search_input:handle_key(mod, key) then
                if key == "Escape" then
                    appmenu_hide()
                    return
                end
                if key == "Up" or key == "Down" or key == "Left" or
                   key == "Right" or key == "Return" or key == "Home" or
                   key == "End" or key == "Tab" then
                    handle_keyboard_navigation(mod, key)
                end
            end

            execute_keybind(key, mod)
        end,
        keyreleased_callback = function(_, mod, key)
            if key == "Control_L" or key == "Control_R" then
                appmenu_data.control_pressed = false
                appmenu_data.wibox:emit_signal("property::current_focus")
            end
        end,
        stop_callback = function()
            appmenu_data.wibox.visible = false
        end
    }

    return appmenu_data.wibox
end

function appmenu_show()
    if not appmenu_data.wibox then return end

    scan_desktop_files()

    appmenu_data.wibox.screen = mouse.screen
    appmenu_data.control_pressed = false

    if client.focus then
        client.focus = nil
    end

    if appmenu_data.search_input then
        appmenu_data.search_input:set_text("")
    end

    update_filtered_list("")
    refresh_menu_widget()

    appmenu_data.current_start = 1
    appmenu_data.current_focus = { type = "pinned", index = 1, pin_focused = false, info_focused = false }
    appmenu_data.wibox:emit_signal("property::current_focus")

    awful.placement.centered(appmenu_data.wibox, {honor_workarea = true})

    if appmenu_data.keygrabber then
        appmenu_data.keygrabber:start()
    end
    awful.placement.centered(appmenu_data.wibox)
    appmenu_data.wibox.visible = true
end

function appmenu_hide()
    if not appmenu_data.wibox then return end

    appmenu_data.wibox.visible = false
    if appmenu_data.keygrabber then
        appmenu_data.keygrabber:stop()
    end
    appmenu_data.wibox:emit_signal("property::current_focus")

    local c = awful.mouse.client_under_pointer()
    if c then
        client.focus = c
        c:raise()
    end
end

function appmenu_toggle()
    if not appmenu_data.wibox then return end
    if appmenu_data.wibox.visible then
        appmenu_hide()
    else
        appmenu_show()
    end
end

return appmenu_data