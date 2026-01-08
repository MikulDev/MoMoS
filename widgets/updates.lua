local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local wibox = require("wibox")
local dpi = require("beautiful.xresources").apply_dpi
local config = require("config")
local util = require("util")
local naughty = require("naughty")

local config_dir = gears.filesystem.get_configuration_dir()
local theme = load_util("theme")

-- Initialize module
local updates = {}

-- Package storage
updates.packages = {}
updates.popup = nil
updates.button = nil
updates.is_updating = false
updates.update_processes = {}
updates.hovered = false

-- Scrolling state
local scroll_state = {
    start_idx = 1,
    items_per_page = 10,
}

local function set_button_text(text)
    if updates.button then
        updates.button:update_text(text)
    end
end

-- Parse checkupdates output
local function parse_updates(output, aur_packages)
    local packages = {}
    local aur_set = {}

    -- Create a set of AUR package names for quick lookup
    if aur_packages then
        for pkg in aur_packages:gmatch("[^\r\n]+") do
            local name = pkg:match("^(%S+)")
            if name then
                aur_set[name] = true
            end
        end
    end

    for line in output:gmatch("[^\r\n]+") do
        -- yay -Qu format: "package_name old_version -> new_version"
        local pkg_name, old_ver, new_ver = line:match("^(%S+)%s+(%S+)%s+%->%s+(%S+)")
        if pkg_name and new_ver then
            table.insert(packages, {
                name = pkg_name,
                old_version = old_ver,
                new_version = new_ver,
                is_aur = aur_set[pkg_name] or pkg_name:match("%-git$") ~= nil,
                updating = false
            })
        end
    end
    return packages
end

-- Function to check for updates
local function check_updates(callback)
    -- First get list of AUR packages, then get all updates
    awful.spawn.easy_async_with_shell("yay -Qm 2>/dev/null", function(aur_stdout)
        -- Now get all updates
        awful.spawn.easy_async_with_shell("yay -Qu 2>/dev/null", function(stdout, stderr, reason, exit_code)
            if stdout ~= "" then
                updates.packages = parse_updates(stdout, aur_stdout)
                -- Sort packages alphabetically by name
                table.sort(updates.packages, function(a, b)
                    return a.name:lower() < b.name:lower()
                end)
            else
                updates.packages = {}
            end

            set_button_text(tostring(#updates.packages))

            if callback then
                callback()
            end
        end)
    end)
end

-- Function to update a single package
local function update_package(pkg, widget_callback)
    if updates.is_updating then
        return
    end

    pkg.updating = true
    if widget_callback then widget_callback() end

    -- Run update command with Zenity password prompt
    local command = string.format("yay -S %s --noconfirm", pkg.name)
    local update_cmd = string.format(
        config.terminal .. " -e sh -c \"%s\"",
        command
    )

    local process = awful.spawn.easy_async_with_shell(update_cmd, function(stdout, stderr, reason, exit_code)
        pkg.updating = false

        -- Remove from process table
        for i, p in ipairs(updates.update_processes) do
            if p == process then
                table.remove(updates.update_processes, i)
                break
            end
        end

        if exit_code == 0 then
            -- Remove package from list
            for i, p in ipairs(updates.packages) do
                if p.name == pkg.name then
                    table.remove(updates.packages, i)
                    break
                end
            end

            -- Update count
            set_button_text(tostring(#updates.packages))

            -- Refresh the popup if visible
            if updates.popup and updates.popup.visible then
                updates.popup.widget = create_update_list()
                select_package_under_mouse()
            end
        end

        if widget_callback then widget_callback() end
    end)

    table.insert(updates.update_processes, process)
end

-- Function to update all packages
local function update_all_packages()
    if updates.is_updating or #updates.packages == 0 then
        return
    end

    updates.is_updating = true

    -- Run full system update with Zenity password prompt
    local command = "yay -Syu --noconfirm"
    local update_cmd = string.format(
        config.terminal .. " -e sh -c \"%s\"",
        command
    )

    updates_hide()
    awful.spawn.easy_async_with_shell(update_cmd, function(stdout, stderr, reason, exit_code)
        updates.is_updating = false

        if exit_code == 0 then
            updates.packages = {}

            -- Update count
            set_button_text("0")
        else
            -- Recheck for remaining updates
            check_updates(function()
                if updates.popup and updates.popup.visible then
                    updates.popup.widget = create_update_list()
                end
            end)
        end
    end)
end

-- Select package widget under mouse after refresh
function select_package_under_mouse()
    if updates.popup and updates.popup.visible then
        gears.timer.start_new(0.01, function()
            if mouse.current_widget then
                mouse.current_widget:emit_signal("mouse::enter")
            end
            return false
        end)
    end
end

-- Create individual package widget
local function create_package_widget(pkg)
    local update_button = create_image_button({
        image_path = config_dir .. "theme-icons/update.png",
        image_size = dpi(16),
        padding = dpi(7),
        button_size = dpi(32),
        opacity = 0.5,
        opacity_hover = 1,
        fg_color = theme.updates.button_fg,
        hover_fg = theme.updates.button_fg_focus,
        bg_color = theme.updates.button_bg,
        border_color = theme.updates.button_border,
        hover_bg = theme.updates.button_bg_focus,
        hover_border = theme.updates.button_border_focus,
        shape_radius = dpi(4),
        on_click = function()
            if not pkg.updating then
                update_package(pkg, function()
                    -- Refresh widget after update
                    if updates.popup and updates.popup.visible then
                        updates.popup.widget = create_update_list()
                    end
                end)
            end
        end,
        id = "update_button"
    })

    -- Package name (left-aligned)
    local pkg_name = wibox.widget {
        text = pkg.name,
        font = font_with_size(theme.update_entry_font_size),
        halign = "left",
        widget = wibox.widget.textbox
    }

    -- AUR indicator (optional, smaller text)
    local aur_indicator = nil
    if pkg.is_aur then
        aur_indicator = wibox.widget {
            markup = '<span foreground="' .. (theme.updates.button_fg_focus or "#888888") .. '" font="' ..
                     font_with_size(theme.update_entry_font_size - 2) .. '">AUR</span>',
            widget = wibox.widget.textbox
        }
    end

    -- Version info (right-aligned)
    local version_info = wibox.widget {
        text = pkg.new_version,
        font = font_with_size(theme.update_entry_font_size - 1),
        halign = "right",
        widget = wibox.widget.textbox
    }

    -- Update indicator
    local updating_indicator = wibox.widget {
        {
            text = "Updating...",
            font = font_with_size(theme.update_entry_font_size - 2),
            widget = wibox.widget.textbox
        },
        visible = pkg.updating,
        widget = wibox.container.background
    }

    -- Left side with package name and optional AUR indicator
    local left_content = wibox.widget {
        pkg_name,
        aur_indicator,
        spacing = dpi(5),
        layout = wibox.layout.fixed.horizontal
    }

    -- Content layout
    local content = wibox.widget {
        {
            left_content,
            nil,
            {
                version_info,
                {
                    updating_indicator,
                    update_button,
                    spacing = dpi(8),
                    layout = wibox.layout.fixed.horizontal
                },
                spacing = dpi(8),
                layout = wibox.layout.fixed.horizontal
            },
            expand = "inside",
            layout = wibox.layout.align.horizontal
        },
        forced_width = dpi(400),
        widget = wibox.container.constraint
    }

    local bg_container = wibox.widget {
        {
            {
                content,
                margins = dpi(8),
                widget = wibox.container.margin
            },
            fg = theme.updates.button_fg,
            bg = theme.updates.entry_bg,
            widget = wibox.container.background,
            shape = function(cr, width, height)
                gears.shape.rounded_rect(cr, width, height, dpi(4))
            end,
            shape_border_width = dpi(1),
            shape_border_color = theme.updates.entry_border,
            id = "package_background"
        },
        top = dpi(5),
        bottom = 0,
        left = dpi(10),
        right = dpi(10),
        widget = wibox.container.margin
    }

    add_hover_cursor(bg_container)

    -- Hover effects
    bg_container:connect_signal("mouse::enter", function()
        local background = bg_container:get_children_by_id("package_background")[1]
        background.bg = theme.updates.entry_bg_hover
        background.shape_border_color = theme.updates.entry_border_hover
    end)
    bg_container:connect_signal("mouse::leave", function()
        local background = bg_container:get_children_by_id("package_background")[1]
        background.bg = theme.updates.entry_bg
        background.shape_border_color = theme.updates.entry_border
    end)

    return bg_container
end

-- Create the update list widget
function create_update_list()
    local list_layout = wibox.layout.fixed.vertical{
        spacing = 0
    }

    -- Calculate items per page
    local max_height = dpi(500)
    local entry_height = dpi(50)
    scroll_state.items_per_page = math.floor((max_height - dpi(80)) / entry_height)

    -- Add visible packages
    local end_idx = math.min(scroll_state.start_idx + scroll_state.items_per_page - 1, #updates.packages)
    for i = scroll_state.start_idx, end_idx do
        local pkg = updates.packages[i]
        local w = create_package_widget(pkg)
        list_layout:add(w)
    end

    -- Create update all button
    local update_all_button = create_image_button({
        image_path = config_dir .. "theme-icons/update_all.png",
        image_size = dpi(20),
        padding = dpi(6),
        opacity = 0.5,
        opacity_hover = 1,
        bg_color = theme.updates.button_bg,
        border_color = theme.updates.button_border,
        fg_color = theme.updates.button_fg,
        hover_bg = theme.updates.button_bg_focus,
        hover_border = theme.updates.button_border_focus,
        hover_fg = theme.updates.button_fg_focus,
        shape_radius = dpi(4),
        on_click = function()
            if not updates.is_updating then
                update_all_packages()
            end
        end
    })

    -- Create refresh button
    local refresh_button = create_image_button({
        image_path = config_dir .. "theme-icons/refresh.png",
        image_size = dpi(20),
        padding = dpi(6),
        opacity = 0.5,
        opacity_hover = 1,
        bg_color = theme.updates.button_bg,
        border_color = theme.updates.button_border,
        fg_color = theme.updates.button_fg,
        hover_bg = theme.updates.button_bg_focus,
        hover_border = theme.updates.button_border_focus,
        hover_fg = theme.updates.button_fg_focus,
        shape_radius = dpi(4),
        on_click = function()
            check_updates(function()
                if updates.popup and updates.popup.visible then
                    scroll_state.start_idx = 1
                    updates.popup.widget = create_update_list()
                end
            end)
        end
    })

    -- Package count label
    local count_text = wibox.widget {
        {
            text = string.format("%d packages available", #updates.packages),
            font = font_with_size(theme.update_entry_font_size - 1),
            halign = "center",
            widget = wibox.widget.textbox
        },
        fg = theme.updates.fg,
        widget = wibox.container.background
    }

    local header = wibox.widget {
        {
            #updates.packages > 0 and update_all_button or nil,
            count_text,
            #updates.packages > 0 and refresh_button or nil,
            layout = wibox.layout.align.horizontal
        },
        margins = dpi(10),
        widget = wibox.container.margin
    }

    local list_widget = wibox.widget {
        list_layout,
        bottom = dpi(12),
        widget = wibox.container.margin
    }

    -- Main widget
    local main_widget = wibox.widget {
        header,
        #updates.packages > 0 and list_widget or nil,
        layout = wibox.layout.fixed.vertical,
        spacing = dpi(0)
    }

    -- Add scroll buttons
    main_widget:buttons(gears.table.join(
        -- Scroll up
        awful.button({}, 4, function()
            if updates.popup.visible and scroll_state.start_idx > 1 then
                scroll_state.start_idx = math.max(1, scroll_state.start_idx - 1)
                updates.popup.widget = create_update_list()
                select_package_under_mouse()
            end
        end),
        -- Scroll down
        awful.button({}, 5, function()
            local last_start_index = #updates.packages - scroll_state.items_per_page + 1
            if updates.popup.visible and scroll_state.start_idx < last_start_index then
                scroll_state.start_idx = math.min(last_start_index, scroll_state.start_idx + 1)
                updates.popup.widget = create_update_list()
                select_package_under_mouse()
            end
        end)
    ))

    return main_widget
end

local function test_not_hovered()
    gears.timer.start_new(0.1, function()
        if not updates.hovered then
            updates_hide()
        end
        return false
    end)
end

function updates_show()
    awful.placement.top_left(updates.popup, {
        margins = {
            top = beautiful.wibar_height + dpi(5),
            left = dpi(5)
        },
        parent = updates.popup.screen
    })
    updates.popup.visible = true
end

function updates_hide()
    updates.popup.visible = false
end

local function toggle_visibility()
    if updates.popup.visible then
        updates_hide()
    else
        updates_show()
    end
end

-- Create the updates button
function updates.create_button()
    local button = create_labeled_image_button({
        image_path = config_dir .. "theme-icons/package.png",
        image_size = dpi(16),
        label_text = "0",
        text_size = 12,
        padding = dpi(3),
        opacity = 0.5,
        opacity_hover = 1,
        fg_color = theme.updates.button_fg,
        hover_fg = theme.updates.button_fg_focus,
        bg_color = theme.updates.button_bg,
        border_color = theme.updates.button_border,
        hover_bg = theme.updates.button_bg_focus,
        hover_border = theme.updates.button_border_focus,
        shape_radius = dpi(4),
        on_click = function()
            if not updates.popup.visible then
                scroll_state.start_idx = 1
                updates.popup.widget = create_update_list()
            end
            updates.popup.screen = mouse.screen
            toggle_visibility()
        end,
        id = "update_button"
    })
    updates.button = button

    updates.button:connect_signal("mouse::enter", function()
        updates.hovered = true
    end)
    updates.button:connect_signal("mouse::leave", function()
        updates.hovered = false
        test_not_hovered()
    end)

    -- Create the popup
    updates.popup = awful.popup {
        widget = create_update_list(),
        bg = theme.updates.bg,
        border_color = beautiful.border_focus,
        border_width = beautiful.border_width,
        ontop = true,
        visible = false,
        shape = function(cr, width, height)
            gears.shape.rounded_rect(cr, width, height, dpi(6))
        end
    }

    updates.popup:connect_signal("mouse::enter", function()
        updates.hovered = true
    end)
    updates.popup:connect_signal("mouse::leave", function()
        updates.hovered = false
        test_not_hovered()
    end)

    -- Initial check for updates
    check_updates()

    -- Periodic update check (every 30 minutes)
    gears.timer {
        timeout = 1800,
        autostart = true,
        callback = function()
            check_updates()
        end
    }

    local layout = wibox.widget {
        button,
        margins = dpi(4),
        widget = wibox.container.margin
    }

    return layout
end

return updates