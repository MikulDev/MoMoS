-- Music widget for Awesome WM using playerctl
local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local wibox = require("wibox")
local dpi = require("beautiful.xresources").apply_dpi
local naughty = require('naughty')
local string = require('string')

local config_dir = gears.filesystem.get_configuration_dir()
local icon_dir = config_dir .. "theme-icons/"
local theme = load_util("theme")
local config = require("config")

-- Create album art cache directory if it doesn't exist
awful.spawn.with_shell("rm -r " .. config_dir .. "album_art_cache")
awful.spawn.with_shell("mkdir -p " .. config_dir .. "album_art_cache")

local music_widget = {
    time = 0,
    last_time = 0,
    current_player = nil,
    current_title = "",
    current_artist = "",
    current_length = 0,
    current_art_path = nil,
    visible = true,
    paused_since = os.time(),
    needs_update = true,
    update_in_progress = false,
    last_successful_update = os.time(),
    max_unresponsive_time = 30,
    current_status = "",
    debug_mode = false
}

-- Debug function
local function debug_print(msg)
    if music_widget.debug_mode then
        naughty.notify({
            title = "Music Widget Debug",
            text = msg,
            timeout = 5
        })
    end
end

-- Timers for position updates and title checks
local position_timer = gears.timer({
    timeout = 0.5,  -- Position updates every 0.5 seconds
    autostart = true
})

local title_check_timer = gears.timer({
    timeout = 0.2,  -- Title checks every 0.2 seconds
    autostart = true
})

-- Default album art when none is available
local default_art = icon_dir .. "music_default.png"

-- Find the best player to use based on priorities
local function get_prioritized_player(callback)
    -- Get the list of active players
    awful.spawn.easy_async_with_shell("playerctl --list-all 2>/dev/null", function(stdout, stderr, reason, exit_code)
        if exit_code ~= 0 or stdout == "" then
            callback(nil)
            return
        end

        -- Convert stdout to a table of player names
        local players = {}
        for player in string.gmatch(stdout, "[^\r\n]+") do
            table.insert(players, player)
        end

        -- Check if the current player is still in the list
        local current_player_active = false
        if music_widget.current_player then
            for _, active in ipairs(players) do
                if active == music_widget.current_player then
                    current_player_active = true
                    break
                end
            end
        end

        -- If current player is still active, keep using it
        if current_player_active then
            callback(music_widget.current_player)
            return
        end

        -- Otherwise, find a new player based on priorities
        local player_to_use = nil

        -- Check if any of the preferred players are active
        for _, preferred in ipairs(config.music_players) do
            for _, active in ipairs(players) do
                if string.find(active:lower(), preferred:lower()) then
                    player_to_use = active
                    break
                end
            end
            if player_to_use then break end
        end

        -- If no match found, use the first player
        if not player_to_use and #players > 0 then
            player_to_use = players[1]
        end

        -- If the player has changed, force an update
        if player_to_use ~= music_widget.current_player then
            music_widget.needs_update = true
            debug_print("Player changed to: " .. (player_to_use or "nil"))
        end

        music_widget.current_player = player_to_use
        callback(player_to_use)
    end)
end

-- Function to create a playerctl command with the correct player
local function playerctl_cmd(command)
    local player = music_widget.current_player
    if player then
        return "playerctl --player=" .. player .. " " .. command
    else
        return "playerctl " .. command
    end
end

function music_widget.play_pause()
    awful.spawn(playerctl_cmd("play-pause"))
    schedule_update()
end

function music_widget.next()
    awful.spawn(playerctl_cmd("next"))
    schedule_update()
end

function music_widget.prev()
    awful.spawn(playerctl_cmd("previous"))
    schedule_update()
end

function schedule_update()
    gears.timer.start_new(0.05, function()
        perform_full_update()
        return false
    end)
end

-- Get a single metadata value with error handling and async operation
local function get_metadata_value(key, default_value, callback)
    local cmd = playerctl_cmd("metadata " .. key)
    awful.spawn.easy_async_with_shell(cmd .. " 2>/dev/null", function(stdout, stderr, reason, exit_code)
        local value = stdout and stdout:match("^(.-)%s*$") or default_value
        callback(value)
    end)
end

-- Function to fetch multiple metadata values in parallel and call the callback when all are done
local function get_metadata_batch(keys, callback)
    local results = {}
    local pending = 0

    -- Count the number of keys we need to fetch
    for _ in pairs(keys) do
        pending = pending + 1
    end

    -- Function to check if all requests are done
    local function check_done()
        if pending <= 0 then
            callback(results)
        end
    end

    -- Request each metadata value
    for key, info in pairs(keys) do
        get_metadata_value(key, info.default, function(value)
            results[key] = value
            pending = pending - 1
            check_done()
        end)
    end

    -- Handle the case where there are no keys
    if pending == 0 then
        callback(results)
    end
end

-- Create control buttons using the utility function from util.lua
local function create_button(icon_name, command, tooltip_text)
    local button = create_image_button({
        image_path = icon_dir .. icon_name .. ".png",
        fallback_text = icon_name == "play" and "▶" or icon_name == "pause" and "⏸" or icon_name == "prev" and "⏮" or icon_name == "next" and "⏭",
        padding = dpi(4),
        button_size = dpi(24),
        opacity = 0.8,
        opacity_hover = 1,
        bg_color = beautiful.music.button_bg,
        border_color = beautiful.music.border .. "55",
        shape_radius = dpi(4),
        on_click = function()
            command()

            return true
        end
    })

    return button
end

-- Format seconds to minutes:seconds
local function format_time(seconds)
    if not seconds or seconds < 0 then
        return "0:00"
    end

    local minutes = math.floor(seconds / 60)
    local remaining_seconds = math.floor(seconds % 60)
    return string.format("%d:%02d", minutes, remaining_seconds)
end

-- Function to get album art with error handling
local function get_album_art(title, callback)
    -- Get art URL asynchronously
    get_metadata_value("mpris:artUrl", "", function(art_url)
        if not art_url or art_url == "" then
            callback(default_art)
            return
        end

        -- If it's a file path, strip the file:// prefix
        if art_url:sub(1, 7) == "file://" then
            local path = art_url:sub(8)
            callback(path)
            return
        end

        -- If it's a remote URL (like Spotify's http/https URLs), use cached version if possible
        if art_url:sub(1, 4) == "http" then
            -- Generate a unique filename based on the URL (use md5sum to create a hash)
            awful.spawn.easy_async_with_shell("echo '" .. art_url .. "' | md5sum | cut -d' ' -f1", function(file_hash)
                file_hash = file_hash:match("^(.-)%s*$")
                local cache_path = config_dir .. "album_art_cache/" .. file_hash .. ".jpg"

                -- Check if we've already cached this art
                awful.spawn.easy_async_with_shell("test -f '" .. cache_path .. "' && echo 'exists'", function(result)
                    if result:match("exists") then
                        callback(cache_path)
                    else
                        -- Download the album art if it's not already cached
                        -- Using curl with a timeout to prevent hanging
                        awful.spawn.with_shell("curl -s -m 5 -o '" .. cache_path .. "' '" .. art_url .. "'")

                        -- Wait a short time for download to complete
                        gears.timer.start_new(0.5, function()
                            callback(cache_path)
                            return false
                        end)
                    end
                end)
            end)
            return
        end

        -- For any other URL format, just use it directly
        callback(art_url)
    end)
end

-- Create the music widget
function music_widget.create()
    -- Create album art widget with rounded corners
    local album_art = wibox.widget {
        {
            {
                id = "art",
                image = default_art,
                resize = true,
                valign = "center",
                widget = wibox.widget.imagebox
            },
            left = dpi(1),
            widget = wibox.container.margin
        },
        forced_width = dpi(36),
        forced_height = dpi(36),
        widget = wibox.container.constraint
    }

    -- Create title and artist widgets
    local title_widget = wibox.widget {
        id = "title",
        markup = string.format('<span color="%s">%s</span>',
            beautiful.music.title_fg or beautiful.music.fg,
            "Not playing"),
        font = font_with_size(dpi(12)),
        widget = wibox.widget.textbox
    }

    local artist_widget = wibox.widget {
        id = "artist",
        markup = "",
        font = font_with_size(dpi(11)),
        widget = wibox.widget.textbox
    }

    -- Player indicator widget
    local player_widget = wibox.widget {
        id = "player",
        markup = "",
        font = font_with_size(dpi(8)),
        widget = wibox.widget.textbox
    }

    -- Create track info container
    local track_info = wibox.widget {
        {
            {
                {
                    title_widget,
                    height = dpi(18),
                    widget = wibox.container.constraint
                },
                artist_widget,
                layout = wibox.layout.fixed.vertical,
                spacing = dpi(2)
            },
            width = dpi(150),
            widget = wibox.container.constraint
        },
        top = dpi(2),
        widget = wibox.container.margin
    }

    -- Create progress bar
    local progress_bar = wibox.widget {
        id = "progress",
        max_value = 100,
        value = 0,
        forced_height = dpi(3),
        color = beautiful.music.progress_fg,
        background_color = beautiful.music.progress_bg,
        widget = wibox.widget.progressbar
    }

    -- Create time display
    local time_display = wibox.widget {
        id = "time",
        markup = string.format('<span color="%s">%s</span>',
            beautiful.music.time_fg or beautiful.music.fg,
            "0:00 / 0:00"),
        font = beautiful.font_small or beautiful.font,
        widget = wibox.widget.textbox
    }

    -- Create control buttons
    local prev_button = create_button("prev", music_widget.prev, "Previous")
    local play_pause_button = create_button("play", music_widget.play_pause, "Play/Pause")
    local next_button = create_button("next", music_widget.next, "Next")

    -- Create controls container
    local controls = wibox.widget {
        {
            {
                prev_button,
                play_pause_button,
                next_button,
                spacing = dpi(4),
                layout = wibox.layout.fixed.horizontal
            },
            halign = "center",
            widget = wibox.container.place
        },
        margins = dpi(3),
        widget = wibox.container.margin
    }

    -- Combine time display and controls
    local control_row = wibox.widget {
        {
            {
                {
                    {
                        time_display,
                        halign = "left",
                        widget = wibox.container.place
                    },
                    bottom = dpi(4),
                    widget = wibox.container.margin
                },
                {
                    controls,
                    halign = "right",
                    widget = wibox.container.place
                },
                layout = wibox.layout.flex.horizontal
            },
            {
                progress_bar,
                right = dpi(4),
                top = dpi(1),
                widget = wibox.container.margin
            },
            spacing = dpi(0),
            layout = wibox.layout.fixed.vertical
        },
        width = dpi(180),
        widget = wibox.container.constraint
    }

    -- Main widget container
    local widget = wibox.widget {
        {
            {
                {
                    album_art,
                    right = dpi(10),
                    widget = wibox.container.margin
                },
                {
                    track_info,
                    right = dpi(10),
                    widget = wibox.container.margin
                },
                control_row,
                layout = wibox.layout.fixed.horizontal
            },
            margins = dpi(4),
            widget = wibox.container.margin
        },
        bg = beautiful.music.bg,
        fg = beautiful.music.fg,
        shape = function(cr, width, height)
            gears.shape.rounded_rect(cr, width, height, dpi(6))
        end,
        shape_border_width = dpi(1),
        shape_border_color = beautiful.music.border,
        widget = wibox.container.background
    }

    -- Update UI elements with metadata
    local function update_ui(status, title, artist, position, length, art_path, player_name)
        local current_time = os.time()

        -- Update visibility state
        if status == "Playing" then
            music_widget.paused_since = os.time()
            -- Always show widget when playing
            if not widget.visible then
                widget.visible = true
            end
        elseif status == "Paused" or status == "Stopped" then
            -- Check timeout only for non-playing states
            if os.time() - music_widget.paused_since > (config.music_widget_timeout or 60) then
                if widget.visible then
                    widget.visible = false
                end
            end
        end

        -- Update album art
        album_art.widget.widget.image = art_path or default_art

        -- Update title and artist with markup for colors
        title_widget:set_markup(string.format('<span color="%s">%s</span>',
            beautiful.music.title_fg or beautiful.music.fg,
            gears.string.xml_escape(clip_text(title or "Not playing", 30))))

        artist_widget:set_markup(string.format('<span color="%s">%s</span>',
            beautiful.music.artist_fg or beautiful.music.fg,
            gears.string.xml_escape(clip_text(artist or "", 30))))

        -- Update player name
        if player_name then
            player_widget:set_markup(string.format('<span color="%s">%s</span>',
                beautiful.music.player_fg or beautiful.music.fg .. "88",
                gears.string.xml_escape(player_name)))
        else
            player_widget:set_markup("")
        end

        -- Update play/pause button
        if status == "Playing" then
            play_pause_button:update_image(icon_dir .. "pause.png")
        else
            play_pause_button:update_image(icon_dir .. "play.png")
        end

        -- Update progress bar
        local percent = 0
        if length and length > 0 then
            percent = (position / length) * 100
        end
        progress_bar:set_value(percent)

        -- Update time display with markup for colors
        local time_text = format_time(position) .. " / " .. format_time(length)
        time_display:set_markup(string.format('<span color="%s">%s</span>',
            beautiful.music.time_fg or beautiful.music.fg,
            gears.string.xml_escape(time_text)))

        -- Store current status
        music_widget.current_status = status
        music_widget.last_successful_update = current_time
    end

    -- Perform a position update
    local function update_position()
        -- Skip if no current player or update in progress
        if not music_widget.current_player or music_widget.update_in_progress then
            return
        end

        -- Get current status
        awful.spawn.easy_async_with_shell(playerctl_cmd("status") .. " 2>/dev/null", function(stdout)
            local status = stdout and stdout:match("^(.-)%s*$") or "Stopped"

            -- If status is empty or bad, player might be closed
            if not status or status == "" then
                debug_print("Empty status, player might be closed")
                music_widget.current_player = nil
                get_prioritized_player(function(player) end)
                return
            end

            -- Get position
            awful.spawn.easy_async_with_shell(playerctl_cmd("position") .. " 2>/dev/null", function(pos_stdout)
                local position = tonumber(pos_stdout and pos_stdout:match("^(.-)%s*$")) or 0
                music_widget.time = position

                -- Update UI with new position but keep other values
                update_ui(
                    status,
                    music_widget.current_title,
                    music_widget.current_artist,
                    position,
                    music_widget.current_length,
                    music_widget.current_art_path,
                    music_widget.current_player
                )
            end)
        end)
    end

    -- Function to recover widget from frozen state
    local function recover_widget()
        debug_print("Recovering widget")

        -- Reset all state
        music_widget.current_player = nil
        music_widget.current_title = ""
        music_widget.needs_update = true
        music_widget.last_successful_update = os.time()

        -- Force update
        check_player_and_update()
    end

    -- Perform a full metadata update
    function perform_full_update()
        -- Skip if update already in progress
        if music_widget.update_in_progress then
            return
        end

        music_widget.update_in_progress = true
        debug_print("Performing full update")

        -- Check for unresponsive state
        local current_time = os.time()
        if (current_time - music_widget.last_successful_update) >= music_widget.max_unresponsive_time then
            debug_print("Widget appears unresponsive, attempting recovery")
            recover_widget()
            music_widget.update_in_progress = false
            return
        end

        -- Ensure we have a current player
        if not music_widget.current_player then
            get_prioritized_player(function(player)
                if not player then
                    -- If no player, show default state
                    widget.visible = false
                    title_widget:set_markup(string.format('<span color="%s">%s</span>',
                        beautiful.music.title_fg or beautiful.music.fg,
                        "Not playing"))
                    artist_widget:set_markup("")
                    player_widget:set_markup("")
                    play_pause_button:update_image(icon_dir .. "play.png")
                    progress_bar:set_value(0)
                    time_display:set_markup(string.format('<span color="%s">%s</span>',
                        beautiful.music.time_fg or beautiful.music.fg,
                        "0:00 / 0:00"))
                    album_art.widget.widget.image = default_art

                    music_widget.update_in_progress = false
                    music_widget.last_successful_update = current_time
                else
                    -- We have a player, continue with update
                    perform_full_update()
                end
            end)
            return
        end

        -- Get player status
        awful.spawn.easy_async_with_shell(playerctl_cmd("status") .. " 2>/dev/null", function(stdout)
            local status = stdout and stdout:match("^(.-)%s*$") or "Stopped"

            -- If status is empty or bad, player might be closed
            if not status or status == "" then
                debug_print("Empty status, player might be closed")
                music_widget.current_player = nil
                music_widget.update_in_progress = false
                return
            end

            -- Get position
            awful.spawn.easy_async_with_shell(playerctl_cmd("position") .. " 2>/dev/null", function(pos_stdout)
                local position = tonumber(pos_stdout and pos_stdout:match("^(.-)%s*$")) or 0
                music_widget.time = position

                -- Define the metadata we need to fetch
                local metadata_keys = {
                    ["xesam:title"] = {default = "Unknown"},
                    ["xesam:artist"] = {default = "Unknown"},
                    ["mpris:length"] = {default = "0"}
                }

                -- Fetch all metadata in parallel
                get_metadata_batch(metadata_keys, function(metadata)
                    local title = metadata["xesam:title"]
                    local artist = metadata["xesam:artist"]
                    local length_str = metadata["mpris:length"]
                    local length = tonumber(length_str) and (tonumber(length_str) / 1000000) or 0

                    -- Store current data
                    music_widget.current_title = title
                    music_widget.current_artist = artist
                    music_widget.current_length = length

                    -- Get album art
                    get_album_art(title, function(art_path)
                        -- Store art path
                        music_widget.current_art_path = art_path

                        -- Update UI with all collected data
                        update_ui(status, title, artist, position, length, art_path, music_widget.current_player)

                        -- Reset update flag
                        music_widget.needs_update = false
                        music_widget.update_in_progress = false
                    end)
                end)
            end)
        end)
    end

    -- Check current track title
    local function check_title_change()
        -- Skip if no current player
        if not music_widget.current_player then
            get_prioritized_player(function(player)
                if player then
                    check_title_change()
                end
            end)
            return
        end

        -- Get current title
        get_metadata_value("xesam:title", "Unknown", function(title)
            -- If title has changed, we need a full update
            if title ~= music_widget.current_title and title ~= "Unknown" then
                debug_print("Track changed: " .. title)
                music_widget.current_title = title
                music_widget.needs_update = true
                perform_full_update()
            end
        end)
    end

    -- Check player and update as needed
    function check_player_and_update()
        -- If no current player, try to find one
        if not music_widget.current_player then
            get_prioritized_player(function(player)
                if player then
                    -- Player found, force an update
                    music_widget.needs_update = true
                    if music_widget.needs_update then
                        perform_full_update()
                    end
                end
            end)
        elseif music_widget.needs_update then
            -- Player exists and update is needed
            perform_full_update()
        end
    end

    -- Toggle widget visibility
    function music_widget.toggle()
        widget.visible = not widget.visible
        music_widget.visible = widget.visible
        if music_widget.visible then
            music_widget.paused_since = os.time()
            music_widget.needs_update = true
            check_player_and_update()
        end
    end

    -- Add a manual recovery function
    function music_widget.recover()
        recover_widget()
        naughty.notify({
            title = "Music Widget",
            text = "Widget reset attempted",
            timeout = 5
        })
    end

    -- Set up position timer
    position_timer:connect_signal("timeout", function()
        update_position()
        return true
    end)

    -- Set up title check timer
    title_check_timer:connect_signal("timeout", function()
        check_title_change()
        return true
    end)

    -- Initial update
    check_player_and_update()

    widget.width = dpi(400)
    return widget
end

return music_widget