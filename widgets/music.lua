-- Music widget for Awesome WM using playerctl
-- Displays track info, album art, progress, and playback controls

local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local wibox = require("wibox")
local dpi = require("beautiful.xresources").apply_dpi

local config_dir = gears.filesystem.get_configuration_dir()
local icon_dir = config_dir .. "theme-icons/"
local cache_dir = config_dir .. "album_art_cache/"
local theme = load_util("theme")
local config = require("config")

-- Ensure cache directory exists
awful.spawn.with_shell("mkdir -p " .. cache_dir)


--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

-- Format seconds to [H:]MM:SS
local function format_time(seconds)
    if not seconds or seconds < 0 then
        return "0:00"
    end

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)

    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, secs)
    end
    return string.format("%d:%02d", minutes, secs)
end

-- Truncate text with ellipsis
local function truncate_text(text, max_len)
    if not text then
        return ""
    end
    if #text <= max_len then
        return text
    end
    return text:sub(1, max_len - 3) .. "..."
end

-- Simple string hash for cache filenames (avoids spawning md5sum)
local function hash_string(str)
    local hash = 5381
    for i = 1, #str do
        hash = ((hash * 33) + str:byte(i)) % 0xFFFFFFFF
    end
    return string.format("%08x", hash)
end

-- Escape shell arguments
local function shell_escape(str)
    return "'" .. str:gsub("'", "'\\''") .. "'"
end


--------------------------------------------------------------------------------
-- Music Widget
--------------------------------------------------------------------------------

local function create_music_widget()
    local widget = {}

    -- State
    local state = {
        player = nil,
        status = "Stopped",
        title = "",
        artist = "",
        position = 0,
        length = 0,
        art_url = "",
        last_art_url = "",
        last_play_time = 0,
        frozen_position = nil,  -- For Firefox time fix
        visible = true,
    }

    -- Configuration
    local hide_timeout = config.music_widget_timeout or 60
    local player_priorities = config.music_players or {}
    local update_interval_playing = 1
    local update_interval_paused = 5

    -- UI element references (set during creation)
    local ui = {}

    -- Timer reference
    local update_timer = nil

    ----------------------------------------------------------------------------
    -- Player Selection
    ----------------------------------------------------------------------------

    local function select_player(callback)
        -- Get all players and their statuses in one command
        local cmd = [[
            players=$(playerctl --list-all 2>/dev/null)
            [ -z "$players" ] && exit 0
            for p in $players; do
                status=$(playerctl --player="$p" status 2>/dev/null || echo "Stopped")
                echo "$p|$status"
            done
        ]]

        awful.spawn.easy_async_with_shell(cmd, function(stdout)
            if stdout == "" then
                callback(nil)
                return
            end

            local players = {}
            local playing_player = nil

            for line in stdout:gmatch("[^\r\n]+") do
                local name, status = line:match("^(.+)|(.+)$")
                if name then
                    table.insert(players, { name = name, status = status })
                    if status == "Playing" and not playing_player then
                        playing_player = name
                    end
                end
            end

            -- Prefer currently playing player
            if playing_player then
                callback(playing_player)
                return
            end

            -- Keep current player if still available
            if state.player then
                for _, p in ipairs(players) do
                    if p.name == state.player then
                        callback(state.player)
                        return
                    end
                end
            end

            -- Select by priority list
            for _, preferred in ipairs(player_priorities) do
                for _, p in ipairs(players) do
                    if p.name:lower():find(preferred:lower(), 1, true) then
                        callback(p.name)
                        return
                    end
                end
            end

            -- Default to first available
            if #players > 0 then
                callback(players[1].name)
            else
                callback(nil)
            end
        end)
    end

    ----------------------------------------------------------------------------
    -- Album Art Handling
    ----------------------------------------------------------------------------

    local function update_album_art(art_url)
        if art_url == state.last_art_url then
            return
        end
        state.last_art_url = art_url

        if not art_url or art_url == "" then
            ui.album_art.image = icon_dir .. "music_default.png"
            return
        end

        -- Local file
        if art_url:sub(1, 7) == "file://" then
            ui.album_art.image = art_url:sub(8)
            return
        end

        -- HTTP URL - download and cache
        if art_url:sub(1, 4) == "http" then
            local cache_file = cache_dir .. hash_string(art_url) .. ".jpg"

            awful.spawn.easy_async_with_shell(
                "[ -f " .. shell_escape(cache_file) .. " ] || " ..
                "curl -s -m 5 -o " .. shell_escape(cache_file) .. " " .. shell_escape(art_url),
                function()
                    -- Only update if this is still the current art
                    if state.last_art_url == art_url then
                        ui.album_art.image = cache_file
                    end
                end
            )
            return
        end

        -- Direct path
        ui.album_art.image = art_url
    end

    ----------------------------------------------------------------------------
    -- Widget Update
    ----------------------------------------------------------------------------

    local function update_ui()
        -- Update title and artist
        ui.title:set_markup(string.format(
            '<span color="%s">%s</span>',
            theme.music.title_fg or theme.music.fg,
            gears.string.xml_escape(truncate_text(state.title, 30))
        ))

        ui.artist:set_markup(string.format(
            '<span color="%s">%s</span>',
            theme.music.artist_fg or theme.music.fg,
            gears.string.xml_escape(truncate_text(state.artist, 30))
        ))

        -- Update play/pause button
        local icon = state.status == "Playing" and "pause" or "play"
        ui.play_pause:update_image(icon_dir .. icon .. ".png")

        -- Update progress and time
        local display_position = state.position
        if state.frozen_position then
            display_position = state.frozen_position
        end

        local progress = 0
        if state.length > 0 then
            progress = (display_position / state.length) * 100
        end

        ui.progress:set_value(progress)
        ui.time:set_markup(string.format(
            '<span color="%s">%s</span>',
            theme.music.time_fg or theme.music.fg,
            format_time(display_position) .. " / " .. format_time(state.length)
        ))

        -- Update album art
        update_album_art(state.art_url)

        -- Handle visibility based on timeout
        if state.status == "Playing" then
            state.last_play_time = os.time()
            ui.container.visible = state.visible
        else
            local elapsed = os.time() - state.last_play_time
            if elapsed > hide_timeout then
                ui.container.visible = false
            end
        end
    end

    local function fetch_and_update()
        select_player(function(player)
            if not player then
                state.player = nil
                ui.container.visible = false
                return
            end

            state.player = player

            -- Single playerctl command with structured output
            -- Using ||| as delimiter since it won't appear in metadata
            local format = "{{status}}|||{{position}}|||{{title}}|||{{artist}}|||{{mpris:length}}|||{{mpris:artUrl}}"
            local cmd = string.format(
                "playerctl --player=%s metadata --format %s 2>/dev/null",
                shell_escape(player),
                shell_escape(format)
            )

            awful.spawn.easy_async_with_shell(cmd, function(stdout)
                if stdout == "" then
                    state.player = nil
                    ui.container.visible = false
                    return
                end

                -- Split by ||| delimiter
                local parts = {}
                for part in (stdout .. "|||"):gmatch("(.-)|||") do
                    table.insert(parts, part)
                end

                local new_status = parts[1] or "Stopped"
                local new_position = (tonumber(parts[2]) or 0) / 1000000  -- microseconds to seconds
                local new_title = parts[3] or "Unknown"
                local new_artist = parts[4] or ""
                local new_length = (tonumber(parts[5]) or 0) / 1000000  -- microseconds to seconds
                local new_art_url = (parts[6] or ""):match("^%s*(.-)%s*$")  -- trim whitespace

                -- Firefox time fix: freeze position when paused
                -- Detect if we just paused (status changed to Paused)
                if new_status == "Paused" and state.status == "Playing" then
                    state.frozen_position = new_position
                elseif new_status == "Playing" then
                    state.frozen_position = nil
                elseif new_status == "Paused" and state.frozen_position then
                    -- Keep frozen position, ignore reported position
                else
                    state.frozen_position = nil
                end

                -- Update state
                state.status = new_status
                state.position = new_position
                state.title = new_title
                state.artist = new_artist
                state.length = new_length
                state.art_url = new_art_url

                update_ui()

                -- Adjust timer interval based on playback state
                if update_timer then
                    local new_interval = new_status == "Playing"
                        and update_interval_playing
                        or update_interval_paused
                    if update_timer.timeout ~= new_interval then
                        update_timer.timeout = new_interval
                    end
                end
            end)
        end)
    end

    ----------------------------------------------------------------------------
    -- Controls
    ----------------------------------------------------------------------------

    local function playerctl(command)
        if state.player then
            awful.spawn("playerctl --player=" .. shell_escape(state.player) .. " " .. command)
        else
            awful.spawn("playerctl " .. command)
        end
    end

    function widget.play_pause()
        -- Unfreeze position when user initiates play
        if state.status == "Paused" then
            state.frozen_position = nil
        end
        playerctl("play-pause")
        gears.timer.start_new(0.1, function()
            fetch_and_update()
            return false
        end)
    end

    function widget.next()
        state.frozen_position = nil
        playerctl("next")
        gears.timer.start_new(0.1, function()
            fetch_and_update()
            return false
        end)
    end

    function widget.prev()
        state.frozen_position = nil
        playerctl("previous")
        gears.timer.start_new(0.1, function()
            fetch_and_update()
            return false
        end)
    end

    function widget.toggle()
        state.visible = not state.visible
        if state.visible then
            state.last_play_time = os.time()
            fetch_and_update()
        end
        ui.container.visible = state.visible
    end

    function widget.stop()
        if update_timer then
            update_timer:stop()
            update_timer = nil
        end
    end

    ----------------------------------------------------------------------------
    -- UI Construction
    ----------------------------------------------------------------------------

    local function create_button(icon_name, on_click)
        local icon_path = icon_dir .. icon_name .. ".png"
        local fallback_text = ({
            play = "▶", pause = "⏸", prev = "⏮", next = "⏭"
        })[icon_name] or "?"

        return create_image_button({
            image_path = icon_path,
            fallback_text = fallback_text,
            padding = dpi(4),
            button_size = dpi(24),
            opacity = 0.8,
            opacity_hover = 1,
            bg_color = theme.music.button_bg,
            border_color = theme.music.border .. "55",
            shape_radius = dpi(4),
            on_click = on_click,
        })
    end

    -- Album art
    local album_art_widget = wibox.widget({
        {
            {
                id = "art",
                image = icon_dir .. "music_default.png",
                resize = true,
                valign = "center",
                widget = wibox.widget.imagebox,
            },
            left = dpi(1),
            widget = wibox.container.margin,
        },
        forced_width = dpi(36),
        forced_height = dpi(36),
        widget = wibox.container.constraint,
    })
    ui.album_art = album_art_widget:get_children_by_id("art")[1]

    -- Track info
    local title_widget = wibox.widget({
        markup = string.format('<span color="%s">Not playing</span>',
            theme.music.title_fg or theme.music.fg),
        font = font_with_size(11),
        widget = wibox.widget.textbox,
    })
    ui.title = title_widget

    local artist_widget = wibox.widget({
        markup = "",
        font = font_with_size(10),
        widget = wibox.widget.textbox,
    })
    ui.artist = artist_widget

    local track_info = wibox.widget({
        {
            {
                {
                    title_widget,
                    height = dpi(22),
                    widget = wibox.container.constraint,
                },
                artist_widget,
                layout = wibox.layout.fixed.vertical,
                spacing = dpi(2),
            },
            width = dpi(150),
            widget = wibox.container.constraint,
        },
        widget = wibox.container.margin,
    })

    -- Progress bar
    local progress_bar = wibox.widget({
        max_value = 100,
        value = 0,
        forced_height = dpi(3),
        color = theme.music.progress_fg,
        background_color = theme.music.progress_bg,
        widget = wibox.widget.progressbar,
    })
    ui.progress = progress_bar

    -- Time display
    local time_widget = wibox.widget({
        markup = string.format('<span color="%s">0:00 / 0:00</span>',
            theme.music.time_fg or theme.music.fg),
        font = font_with_size(11),
        widget = wibox.widget.textbox,
    })
    ui.time = time_widget

    -- Control buttons
    local prev_button = create_button("prev", widget.prev)
    local play_pause_button = create_button("play", widget.play_pause)
    local next_button = create_button("next", widget.next)
    ui.play_pause = play_pause_button

    local controls = wibox.widget({
        {
            {
                prev_button,
                play_pause_button,
                next_button,
                spacing = dpi(4),
                layout = wibox.layout.fixed.horizontal,
            },
            halign = "center",
            widget = wibox.container.place,
        },
        margins = dpi(3),
        widget = wibox.container.margin,
    })

    -- Control row (time + controls + progress)
    local control_row = wibox.widget({
        {
            {
                {
                    {
                        time_widget,
                        halign = "left",
                        widget = wibox.container.place,
                    },
                    bottom = dpi(4),
                    right = dpi(-8),
                    widget = wibox.container.margin,
                },
                {
                    controls,
                    halign = "right",
                    widget = wibox.container.place,
                },
                layout = wibox.layout.flex.horizontal,
            },
            {
                progress_bar,
                right = dpi(4),
                top = dpi(1),
                widget = wibox.container.margin,
            },
            spacing = dpi(0),
            layout = wibox.layout.fixed.vertical,
        },
        width = dpi(210),
        widget = wibox.container.constraint,
    })

    -- Main container
    local container = wibox.widget({
        {
            {
                {
                    album_art_widget,
                    right = dpi(10),
                    widget = wibox.container.margin,
                },
                {
                    track_info,
                    right = dpi(10),
                    widget = wibox.container.margin,
                },
                control_row,
                layout = wibox.layout.fixed.horizontal,
            },
            margins = dpi(4),
            widget = wibox.container.margin,
        },
        bg = theme.music.bg,
        fg = theme.music.fg,
        shape = function(cr, w, h)
            gears.shape.rounded_rect(cr, w, h, dpi(6))
        end,
        shape_border_width = dpi(1),
        shape_border_color = theme.music.border,
        widget = wibox.container.background,
    })
    container.width = dpi(400)
    ui.container = container

    -- Export the container as the widget itself
    widget.widget = container

    ----------------------------------------------------------------------------
    -- Initialization
    ----------------------------------------------------------------------------

    state.last_play_time = os.time()

    update_timer = gears.timer({
        timeout = update_interval_playing,
        autostart = true,
        callback = fetch_and_update,
    })

    -- Initial fetch
    fetch_and_update()

    return widget
end


--------------------------------------------------------------------------------
-- Module Interface
--------------------------------------------------------------------------------

local music_widget = {
    _instance = nil,
}

-- Create and return the widget, storing reference for global functions
function music_widget.create()
    music_widget._instance = create_music_widget()
    return music_widget._instance.widget
end

-- Global control functions (delegate to instance)
function music_widget.play_pause()
    if music_widget._instance then
        music_widget._instance.play_pause()
    end
end

function music_widget.next()
    if music_widget._instance then
        music_widget._instance.next()
    end
end

function music_widget.prev()
    if music_widget._instance then
        music_widget._instance.prev()
    end
end

function music_widget.toggle()
    if music_widget._instance then
        music_widget._instance.toggle()
    end
end

function music_widget.stop()
    if music_widget._instance then
        music_widget._instance.stop()
    end
end

return music_widget