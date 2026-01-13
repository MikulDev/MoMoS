--[[
    Volume Mixer Widget for Awesome WM

    Features:
    - Volume icon button for the wibar
    - Scroll on icon to adjust master volume
    - Click to open per-application volume mixer popup
    - Uses PulseAudio/PipeWire via pactl for volume control
]]

local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local wibox = require("wibox")
local dpi = require("beautiful.xresources").apply_dpi

local BasePopup = require("base_popup")

local config_dir = gears.filesystem.get_configuration_dir()
local icon_dir = config_dir .. "theme-icons/"
local theme = load_util("theme")

--------------------------------------------------------------------------------
-- Volume Icons
--------------------------------------------------------------------------------

local VOLUME_ICONS = {
    high = icon_dir .. "volume_high.png",
    medium = icon_dir .. "volume_medium.png",
    low = icon_dir .. "volume_low.png",
    muted = icon_dir .. "volume_muted.png",
}

-- Fallback to text if icons don't exist
local function get_volume_icon(level, muted)
    if muted then
        return VOLUME_ICONS.muted, "󰖁"
    elseif level > 66 then
        return VOLUME_ICONS.high, "󰕾"
    elseif level > 33 then
        return VOLUME_ICONS.medium, "󰖀"
    else
        return VOLUME_ICONS.low, "󰕿"
    end
end

--------------------------------------------------------------------------------
-- PulseAudio/PipeWire Interface
--------------------------------------------------------------------------------

local pulse = {}

-- Get master volume and mute status
function pulse.get_master_volume(callback)
    awful.spawn.easy_async_with_shell(
        "pactl get-sink-volume @DEFAULT_SINK@ | grep -oP '\\d+%' | head -1 | tr -d '%'",
        function(stdout)
            local volume = tonumber(stdout) or 0
            awful.spawn.easy_async_with_shell(
                "pactl get-sink-mute @DEFAULT_SINK@ | grep -oP 'yes|no'",
                function(mute_stdout)
                    local muted = mute_stdout:match("yes") ~= nil
                    callback(volume, muted)
                end
            )
        end
    )
end

-- Set master volume
function pulse.set_master_volume(level)
    level = math.max(0, math.min(150, level))
    awful.spawn.with_shell(string.format("pactl set-sink-volume @DEFAULT_SINK@ %d%%", level))
end

-- Toggle master mute
function pulse.toggle_master_mute()
    awful.spawn.with_shell("pactl set-sink-mute @DEFAULT_SINK@ toggle")
end

-- Get all sink inputs (applications playing audio)
function pulse.get_sink_inputs(callback)
    awful.spawn.easy_async_with_shell([[
        pactl list sink-inputs 2>/dev/null | awk '
        BEGIN { RS="Sink Input #"; FS="\n" }
        NR > 1 {
            id = ""; name = ""; volume = ""; muted = ""; icon = ""
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^[0-9]+/) {
                    gsub(/[^0-9]/, "", $i)
                    id = $i
                }
                if ($i ~ /application\.name/) {
                    gsub(/.*= "|"$/, "", $i)
                    name = $i
                }
                if ($i ~ /application\.icon_name/) {
                    gsub(/.*= "|"$/, "", $i)
                    icon = $i
                }
                if ($i ~ /Volume:/) {
                    match($i, /[0-9]+%/)
                    volume = substr($i, RSTART, RLENGTH-1)
                }
                if ($i ~ /Mute:/) {
                    muted = ($i ~ /yes/) ? "true" : "false"
                }
            }
            if (id != "" && name != "") {
                print id "|" name "|" volume "|" muted "|" icon
            }
        }'
    ]], function(stdout)
        local inputs = {}
        for line in stdout:gmatch("[^\r\n]+") do
            local id, name, volume, muted, icon = line:match("([^|]+)|([^|]+)|([^|]*)|([^|]*)|([^|]*)")
            if id and name then
                table.insert(inputs, {
                    id = id,
                    name = name,
                    volume = tonumber(volume) or 100,
                    muted = muted == "true",
                    icon = icon ~= "" and icon or nil
                })
            end
        end
        callback(inputs)
    end)
end

-- Set sink input volume
function pulse.set_sink_input_volume(id, level)
    level = math.max(0, math.min(150, level))
    awful.spawn.with_shell(string.format("pactl set-sink-input-volume %s %d%%", id, level))
end

-- Toggle sink input mute
function pulse.toggle_sink_input_mute(id)
    awful.spawn.with_shell(string.format("pactl set-sink-input-mute %s toggle", id))
end

--------------------------------------------------------------------------------
-- Volume Mixer Popup
--------------------------------------------------------------------------------

local volume_mixer = {}
volume_mixer.__index = volume_mixer
setmetatable(volume_mixer, { __index = BasePopup })

function volume_mixer.new()
    local self = BasePopup.new({
        name = "volume_mixer",

        -- Appearance
        bg = theme.volume.bg,
        border_color = theme.volume.border,
        shape_radius = dpi(12),

        -- Size - use explicit width to prevent expansion
        width = dpi(340),

        -- Behavior
        show_overlay = false,
        wrap_navigation = true,
        unfocus_clients = false,

        -- Content margin
        content_margin = dpi(12),
    })

    setmetatable(self, volume_mixer)

    self._master_slider = nil
    self._master_icon = nil
    self._app_container = nil
    self._app_items = {}
    self._refresh_timer = nil

    return self
end

-- Create a volume slider widget
function volume_mixer:_create_slider(initial_value, on_change)
    local slider = wibox.widget {
        bar_shape = function(cr, w, h)
            gears.shape.rounded_rect(cr, w, h, dpi(4))
        end,
        bar_height = dpi(6),
        bar_color = theme.volume.slider_bg,
        bar_active_color = theme.volume.slider_fg,
        bar_border_color = theme.volume.slider_border,
        bar_border_width = dpi(1),
        handle_shape = gears.shape.circle,
        handle_width = dpi(16),
        handle_color = theme.volume.slider_handle,
        handle_border_width = dpi(1),
        handle_border_color = theme.volume.slider_handle_border,
        value = initial_value,
        minimum = 0,
        maximum = 100,
        forced_height = dpi(20),
        forced_width = dpi(200),  -- Prevent infinite expansion
        widget = wibox.widget.slider,
    }

    slider:connect_signal("property::value", function(s)
        if on_change then
            on_change(s.value)
        end
    end)

    return slider
end

-- Create the master volume section
function volume_mixer:_create_master_section()
    local icon_path, fallback = get_volume_icon(100, false)

    icon_widget = wibox.widget {
        image = get_volume_icon(100, false),
        widget = wibox.widget.imagebox
    }

    local function update_icon()
        pulse.get_master_volume(function(volume, muted)
            local icon_path = get_volume_icon(volume, muted)
            icon_widget.image = icon_path
            icon_widget.opacity = muted and 0.5 or 1
        end)
    end

    self._master_icon = create_image_button({
        widget = icon_widget,
        padding = dpi(6),
        bg_color = theme.volume.button_bg,
        border_color = theme.volume.button_border,
        hover_bg = theme.volume.button_bg_focus,
        hover_border = theme.volume.button_border_focus,
        shape_radius = dpi(6),
        on_click = function()
            pulse.toggle_master_mute()
            gears.timer.start_new(0.1, function()
                self:_update_master_volume()
                update_icon()
                return false
            end)
        end,
    })
    update_icon()
    self._master_icon.forced_width = dpi(32)
    self._master_icon.forced_height = dpi(32)

    self._master_slider = self:_create_slider(100, function(value)
        pulse.set_master_volume(value)
    end)

    self._master_label = wibox.widget {
        text = "100%",
        font = font_with_size(11),
        align = "right",
        forced_width = dpi(45),
        widget = wibox.widget.textbox,
    }

    return wibox.widget {
        {
            {
                {
                    text = "Master Volume",
                    font = font_with_size(12),
                    widget = wibox.widget.textbox,
                },
                fg = theme.volume.fg_title,
                widget = wibox.container.background,
            },
            nil,
            {
                self._master_label,
                fg = theme.volume.fg,
                widget = wibox.container.background,
            },
            layout = wibox.layout.align.horizontal,
        },
        {
            self._master_icon,
            {
                self._master_slider,
                left = dpi(12),
                widget = wibox.container.margin,
            },
            layout = wibox.layout.align.horizontal,
        },
        spacing = dpi(8),
        layout = wibox.layout.fixed.vertical,
    }
end

-- Create an application volume row
function volume_mixer:_create_app_row(app)
    local item = {}

    -- Try to find app icon
    local icon_widget
    local icon_path = nil

    if app.icon then
        -- Try to find the icon using the icon theme
        icon_path = gears.filesystem.file_readable("/usr/share/icons/hicolor/48x48/apps/" .. app.icon .. ".png")
            and "/usr/share/icons/hicolor/48x48/apps/" .. app.icon .. ".png"
            or nil
    end

    if icon_path then
        icon_widget = wibox.widget {
            image = icon_path,
            resize = true,
            forced_width = dpi(24),
            forced_height = dpi(24),
            widget = wibox.widget.imagebox,
        }
    else
        -- Use a generic speaker icon or first letter
        icon_widget = wibox.widget {
            text = app.name:sub(1, 1):upper(),
            font = font_with_size(12),
            align = "center",
            valign = "center",
            widget = wibox.widget.textbox,
        }
    end

    item.icon_container = wibox.widget {
        {
            icon_widget,
            halign = "center",
            valign = "center",
            widget = wibox.container.place,
        },
        bg = theme.volume.button_bg,
        shape = function(cr, w, h)
            gears.shape.rounded_rect(cr, w, h, dpi(6))
        end,
        forced_width = dpi(32),
        forced_height = dpi(32),
        widget = wibox.container.background,
    }

    -- Mute toggle on icon click
    item.icon_container:buttons(gears.table.join(
        awful.button({}, 1, function()
            pulse.toggle_sink_input_mute(app.id)
            gears.timer.start_new(0.1, function()
                self:_refresh_apps()
                return false
            end)
        end)
    ))

    if add_hover_cursor then
        add_hover_cursor(item.icon_container)
    end

    item.slider = self:_create_slider(app.volume, function(value)
        pulse.set_sink_input_volume(app.id, value)
    end)

    item.volume_label = wibox.widget {
        text = app.volume .. "%",
        font = font_with_size(10),
        align = "right",
        forced_width = dpi(40),
        widget = wibox.widget.textbox,
    }

    -- Update visual for muted state
    if app.muted then
        item.icon_container.opacity = 0.5
        item.slider.bar_active_color = theme.volume.fg_muted
    end

    item.container = wibox.widget {
        {
            {
                {
                    {
                        text = app.name,
                        font = font_with_size(11),
                        ellipsize = "end",
                        widget = wibox.widget.textbox,
                    },
                    fg = app.muted and theme.volume.fg_muted or theme.volume.fg,
                    widget = wibox.container.background,
                },
                nil,
                {
                    item.volume_label,
                    fg = theme.volume.fg,
                    widget = wibox.container.background,
                },
                layout = wibox.layout.align.horizontal,
            },
            {
                item.icon_container,
                {
                    item.slider,
                    left = dpi(10),
                    widget = wibox.container.margin,
                },
                layout = wibox.layout.align.horizontal,
            },
            spacing = dpi(2),
            layout = wibox.layout.fixed.vertical,
        },
        margins = dpi(6),
        left = dpi(10),
        right = dpi(10),
        widget = wibox.container.margin,
    }

    item.wrapper = wibox.widget {
        item.container,
        bg = theme.volume.app_bg,
        shape_border_color = theme.volume.app_border,
        shape_border_width = dpi(1),
        shape = function(cr, w, h)
            gears.shape.rounded_rect(cr, w, h, dpi(8))
        end,
        widget = wibox.container.background,
    }

    item.wrapper:connect_signal("mouse::enter", function()
        item.wrapper.bg = theme.volume.app_bg_hover
    end)

    item.wrapper:connect_signal("mouse::leave", function()
        item.wrapper.bg = theme.volume.app_bg
    end)

    return item
end

-- Update master volume display
function volume_mixer:_update_master_volume()
    pulse.get_master_volume(function(volume, muted)
        if self._master_slider then
            self._master_slider.value = volume
        end
        if self._master_label then
            self._master_label.text = volume .. "%"
        end
        if self._master_icon then
            local icon_path = get_volume_icon(volume, muted)
            local icon = self._master_icon:get_children_by_id("icon")[1]
            if icon then
                icon.image = icon_path
            end
            self._master_icon.opacity = muted and 0.5 or 1
        end
    end)
end

-- Refresh application list
function volume_mixer:_refresh_apps()
    pulse.get_sink_inputs(function(apps)
        if not self._app_container then return end

        self._app_container:reset()
        self._app_items = {}

        if #apps == 0 then
            local no_apps = wibox.widget {
                {
                    {
                        text = "No applications playing audio",
                        font = font_with_size(11),
                        align = "center",
                        widget = wibox.widget.textbox,
                    },
                    fg = theme.volume.fg_muted,
                    widget = wibox.container.background,
                },
                margins = dpi(20),
                widget = wibox.container.margin,
            }
            self._app_container:add(no_apps)
        else
            for _, app in ipairs(apps) do
                local item = self:_create_app_row(app)
                table.insert(self._app_items, item)
                self._app_container:add(item.wrapper)
            end
        end
    end)
end

-- Create popup content
function volume_mixer:create_content()
    self:clear_items()
    self._app_items = {}

    local master_section = self:_create_master_section()

    -- Separator
    local separator = wibox.widget {
        {
            orientation = "horizontal",
            forced_height = dpi(1),
            color = theme.volume.separator,
            widget = wibox.widget.separator,
        },
        top = dpi(8),
        bottom = dpi(8),
        widget = wibox.container.margin,
    }

    -- Applications header
    local apps_header = wibox.widget {
        {
            text = "Applications",
            font = font_with_size(12),
            widget = wibox.widget.textbox,
        },
        fg = theme.volume.fg_title,
        widget = wibox.container.background,
    }

    -- Container for app rows
    self._app_container = wibox.widget {
        spacing = dpi(8),
        layout = wibox.layout.fixed.vertical,
    }

    -- Initial refresh
    self:_update_master_volume()
    self:_refresh_apps()

    -- Wrap everything in a constraint to enforce width
    return wibox.widget {
        {
            master_section,
            separator,
            apps_header,
            {
                self._app_container,
                top = dpi(8),
                bottom = dpi(1),
                widget = wibox.container.margin,
            },
            spacing = dpi(4),
            layout = wibox.layout.fixed.vertical,
        },
        strategy = "exact",
        width = dpi(316),  -- 340 - 24 (content_margin * 2)
        widget = wibox.container.constraint,
    }
end

-- Override show to start refresh timer
function volume_mixer:on_show()
    self._refresh_timer = gears.timer {
        timeout = 2,
        autostart = true,
        callback = function()
            if self:is_visible() then
                self:_update_master_volume()
                self:_refresh_apps()
            end
        end
    }
end

-- Override hide to stop refresh timer
function volume_mixer:on_hide()
    if self._refresh_timer then
        self._refresh_timer:stop()
        self._refresh_timer = nil
    end
end

--------------------------------------------------------------------------------
-- Volume Button Widget (for wibar)
--------------------------------------------------------------------------------

local volume_button = {}

function volume_button.create()
    local mixer_popup = nil
    local button = nil
    local icon_widget = nil
    local update_timer = nil

    -- Create icon widget
    icon_widget = wibox.widget {
        image = VOLUME_ICONS.high,
        widget = wibox.widget.imagebox
    }

    -- Function to update icon based on volume
    local function update_icon()
        pulse.get_master_volume(function(volume, muted)
            local icon_path = get_volume_icon(volume, muted)
            icon_widget.image = icon_path
            icon_widget.opacity = muted and 0.5 or 1
        end)
    end

    -- Create button using the helper function
    button = create_image_button({
        widget = icon_widget,
        padding = dpi(6),
        bg_color = theme.volume.button_bg,
        border_color = theme.volume.button_border,
        hover_bg = theme.volume.button_bg_focus,
        hover_border = theme.volume.button_border_focus,
        shape_radius = dpi(6),
        on_click = function()
            if not mixer_popup then
                mixer_popup = volume_mixer.new()
                mixer_popup:init()
            end

            -- Fallback to placing near mouse
            mixer_popup.placement = function(p)
                awful.placement.top_right(p)
                awful.placement.no_offscreen(p, {honor_workarea = true, margins = dpi(10)})
            end

            mixer_popup:toggle()
            update_icon()
        end,
    })

    -- Scroll to adjust volume
    button:buttons(gears.table.join(
        button:buttons(),
        awful.button({}, 4, function()  -- Scroll up
            pulse.get_master_volume(function(volume, muted)
                pulse.set_master_volume(volume + 5)
                gears.timer.start_new(0.05, function()
                    update_icon()
                    return false
                end)
            end)
        end),
        awful.button({}, 5, function()  -- Scroll down
            pulse.get_master_volume(function(volume, muted)
                pulse.set_master_volume(volume - 5)
                gears.timer.start_new(0.05, function()
                    update_icon()
                    return false
                end)
            end)
        end),
        awful.button({}, 2, function()  -- Middle click to mute
            pulse.toggle_master_mute()
            gears.timer.start_new(0.1, function()
                update_icon()
                return false
            end)
        end)
    ))

    -- Initial update
    update_icon()

    -- Periodic update
    update_timer = gears.timer {
        timeout = 5,
        autostart = true,
        callback = update_icon
    }

    -- Container with margins matching systray style
    local container = wibox.widget {
        {
            button,
            top = dpi(4),
            bottom = dpi(4),
            widget = wibox.container.margin,
        },
        widget = wibox.container.background,
    }

    -- Store references for external access
    container._button = button
    container._update = update_icon
    container._mixer = function() return mixer_popup end

    return container
end

--------------------------------------------------------------------------------
-- Module Interface
--------------------------------------------------------------------------------

local volume_instance = nil

local function volume_init()
    -- Nothing to initialize globally
    return true
end

local function volume_create_button()
    return volume_button.create()
end

local function volume_show()
    if volume_instance then
        volume_instance:show()
    end
end

local function volume_hide()
    if volume_instance then
        volume_instance:hide()
    end
end

local function volume_toggle()
    if volume_instance then
        volume_instance:toggle()
    end
end

return {
    init = volume_init,
    create_button = volume_create_button,
    show = volume_show,
    hide = volume_hide,
    toggle = volume_toggle,

    -- Export classes for direct use
    volume_button = volume_button,
    volume_mixer = volume_mixer,
}