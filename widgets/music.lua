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

-- Set default player priorities if not defined in config
if not config.music_players then
    config.music_players = {"spotify", "firefox", "chromium", "mpv"}
end

local music_widget = {
    time = 0,
    last_time = 0,
    current_player = nil,
    metadata_cache = {},
    last_update = 0,
    update_interval = 1,  -- Full metadata update every 1 second
    position_update_interval = 0.5, -- Increased from 0.2 to 0.5 seconds
    player_check_interval = 5,  -- Check for new players every 5 seconds
    last_player_check = 0,
    paused_since = os.time(),
    visible = true,
    -- New fields for improved stability
    last_reset = os.time(),
    reset_interval = 120, -- Reset cache every 2 minutes
    last_successful_update = os.time(),
    max_unresponsive_time = 30, -- Consider widget frozen after 30 seconds without update
    last_title = "", -- Track the last title to detect song changes
    max_cache_age = 60, -- Maximum cache age in seconds
    debug_mode = false -- Set to true to enable debug notifications
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

-- Single combined timer for all update operations
local timer = gears.timer({
    timeout = music_widget.position_update_interval,
    autostart = true
})

-- Default album art when none is available
local default_art = icon_dir .. "music_default.png"

-- Get prioritized player, using caching to avoid frequent checks
local function get_prioritized_player()
    local current_time = os.time()

    -- Only check for new players periodically to reduce overhead
    if (current_time - music_widget.last_player_check) >= music_widget.player_check_interval then
        -- Get the list of active players
        awful.spawn.easy_async_with_shell("playerctl --list-all 2>/dev/null", function(stdout, stderr, reason, exit_code)
            if exit_code ~= 0 or stdout == "" then
                music_widget.current_player = nil
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

            -- If the player has changed, clear the metadata cache
            if player_to_use ~= music_widget.current_player then
                music_widget.metadata_cache = {}
                debug_print("Player changed to: " .. (player_to_use or "nil"))
            end

            music_widget.current_player = player_to_use
        end)

        music_widget.last_player_check = current_time
    end

    return music_widget.current_player
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

-- Get a single metadata value with error handling and async operation
local function get_metadata_value(key, default_value, callback)
    -- Use cached value if available, not expired, and not too old
    local current_time = os.time()
    if music_widget.metadata_cache[key] and
       (current_time - music_widget.metadata_cache[key].timestamp) < music_widget.update_interval and
       (current_time - music_widget.metadata_cache[key].timestamp) < music_widget.max_cache_age then
        callback(music_widget.metadata_cache[key].value)
        return
    end

    -- Otherwise, get the value and cache it asynchronously
    local cmd = playerctl_cmd("metadata " .. key)

    awful.spawn.easy_async_with_shell(cmd .. " 2>/dev/null", function(stdout, stderr, reason, exit_code)
        local value = stdout and stdout:match("^(.-)%s*$") or default_value

        music_widget.metadata_cache[key] = {
            value = value,
            timestamp = current_time
        }

        callback(value)
    end)
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
            awful.spawn(playerctl_cmd(command))
            -- Use a delayed update after button click
            gears.timer.start_new(0.25, function()
                music_widget.update(true)
                return false
            end)
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

-- Function to get album art with caching and error handling
local function get_album_art(callback)
    -- Use cached album art if available
    if music_widget.metadata_cache["albumArt"] and
       (os.time() - music_widget.metadata_cache["albumArt"].timestamp) < music_widget.max_cache_age then
        callback(music_widget.metadata_cache["albumArt"].value)
        return
    end

    -- Get art URL asynchronously
    get_metadata_value("mpris:artUrl", "", function(art_url)
        if not art_url or art_url == "" then
            music_widget.metadata_cache["albumArt"] = {
                value = default_art,
                timestamp = os.time()
            }
            callback(default_art)
            return
        end

        -- If it's a file path, strip the file:// prefix
        if art_url:sub(1, 7) == "file://" then
            local path = art_url:sub(8)
            music_widget.metadata_cache["albumArt"] = {
                value = path,
                timestamp = os.time()
            }
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
                        music_widget.metadata_cache["albumArt"] = {
                            value = cache_path,
                            timestamp = os.time()
                        }
                        callback(cache_path)
                    else
                        -- Download the album art if it's not already cached
                        -- Using curl with a timeout to prevent hanging
                        awful.spawn.with_shell("curl -s -m 5 -o '" .. cache_path .. "' '" .. art_url .. "'")

                        -- Wait a short time for download to complete
                        gears.timer.start_new(0.5, function()
                            music_widget.metadata_cache["albumArt"] = {
                                value = cache_path,
                                timestamp = os.time()
                            }
                            callback(cache_path)
                            return false
                        end)
                    end
                end)
            end)
            return
        end

        -- For any other URL format, just use it directly
        music_widget.metadata_cache["albumArt"] = {
            value = art_url,
            timestamp = os.time()
        }
        callback(art_url)
    end)
end

-- Function to recover widget from frozen state
local function recover_widget()
    debug_print("Recovering widget")

    -- Reset all state
    music_widget.metadata_cache = {}
    music_widget.current_player = nil
    music_widget.last_update = 0
    music_widget.last_player_check = 0
    music_widget.last_successful_update = os.time()
    music_widget.last_reset = os.time()

    -- Force a full update on next timer tick
    music_widget.update(true)
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
            shape = function(cr, width, height)
                gears.shape.rounded_rect(cr, width, height, dpi(4))
            end,
            shape_border_width = 0,
            widget = wibox.container.background
        },
        forced_width = dpi(40),
        forced_height = dpi(40),
        widget = wibox.container.constraint
    }

    -- Create title and artist widgets
    local title_widget = wibox.widget {
        id = "title",
        markup = string.format('<span color="%s">%s</span>',
            beautiful.music.title_fg or beautiful.music.fg,
            "Not playing"),
        font = font_with_size(dpi(13)),
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
            title_widget,
            artist_widget,
            --player_widget,
            layout = wibox.layout.fixed.vertical,
            spacing = dpi(-2)
        },
        forced_width = dpi(150),
        widget = wibox.container.constraint
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
    local prev_button = create_button("prev", "previous", "Previous")
    local play_pause_button = create_button("play", "play-pause", "Play/Pause")
    local next_button = create_button("next", "next", "Next")

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
            bottom = dpi(2),
            widget = wibox.container.margin
        },
        spacing = dpi(0),
        layout = wibox.layout.fixed.vertical
    }

    -- Main widget container
    local widget = wibox.widget {
        {
            {
                {
                    album_art,
                    right = dpi(8),
                    widget = wibox.container.margin
                },
                {
                    track_info,
                    right = dpi(8),
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

    -- Flag to track if title/artist need update
    local needs_text_update = true
    local last_status = ""
    local last_title = ""
    local last_artist = ""
    local last_player = ""
    local update_in_progress = false

    -- Rewritten update function with improved stability
    function music_widget.update(force_update)
        -- Prevent concurrent updates
        if update_in_progress then
            debug_print("Update already in progress, skipping")
            return
        end

        update_in_progress = true

        -- Don't force visibility here - we'll handle visibility based on status later
        -- Only an early return if visibility is explicitly off
        if not music_widget.visible then
            widget.visible = false
            update_in_progress = false
            return
        end

        -- Check for unresponsive state
        local current_time = os.time()
        if (current_time - music_widget.last_successful_update) >= music_widget.max_unresponsive_time then
            debug_print("Widget appears unresponsive, attempting recovery")
            recover_widget()
        end

        -- Check if time for a periodic reset
        if (current_time - music_widget.last_reset) >= music_widget.reset_interval then
            debug_print("Performing periodic reset")
            music_widget.metadata_cache = {}
            music_widget.last_reset = current_time
            force_update = true
        end

        -- Ensure we have a current player
        if not music_widget.current_player then
            -- Force an immediate player check
            music_widget.last_player_check = 0
            get_prioritized_player()
        end

        -- If still no player, show default state
        if not music_widget.current_player then
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

            update_in_progress = false
            music_widget.last_successful_update = current_time
            return
        end

        -- Get player status asynchronously first
        awful.spawn.easy_async_with_shell(playerctl_cmd("status") .. " 2>/dev/null", function(stdout)
            local status = stdout and stdout:match("^(.-)%s*$") or "Stopped"

            -- If status is empty or bad, player might be closed
            if not status or status == "" then
                debug_print("Empty status, player might be closed")
                music_widget.current_player = nil
                music_widget.metadata_cache = {}
                update_in_progress = false

                -- Retry after a delay
                gears.timer.start_new(1, function()
                    music_widget.update(true)
                    return false
                end)
                return
            end

            -- Get position asynchronously
            awful.spawn.easy_async_with_shell(playerctl_cmd("position") .. " 2>/dev/null", function(pos_stdout)
                local position = tonumber(pos_stdout and pos_stdout:match("^(.-)%s*$")) or 0
                music_widget.time = position

                -- If this is a full update, get full metadata
                if force_update or (current_time - music_widget.last_update) >= music_widget.update_interval then
                    -- Get title
                    get_metadata_value("xesam:title", "Unknown", function(title)
                        -- Get artist
                        get_metadata_value("xesam:artist", "Unknown", function(artist)
                            -- Get length
                            get_metadata_value("mpris:length", "0", function(length_str)
                                local length = tonumber(length_str) and (tonumber(length_str) / 1000000) or 0

                                -- Get album art
                                get_album_art(function(art_path)
                                    -- Now update the widget with all data

                                    -- Check if track changed
                                    if title ~= music_widget.last_title then
                                        debug_print("Track changed: " .. title)
                                        force_update = true
                                        music_widget.last_title = title
                                    end

                                    -- Update visibility state
                                    if status == "Playing" then
                                        music_widget.paused_since = os.time()
                                        -- Always show widget when playing
                                        if not widget.visible then
                                            widget.visible = true
                                        end
                                    elseif status == "Paused" or status == "Stopped" then
                                        -- Check timeout only for non-playing states
                                        if os.time() - music_widget.paused_since > config.music_widget_timeout then
                                            if widget.visible then
                                                widget.visible = false
                                            end
                                        end
                                    end

                                    -- Check if text needs updating
                                    needs_text_update = force_update or
                                                    status ~= last_status or
                                                    title ~= last_title or
                                                    artist ~= last_artist or
                                                    music_widget.current_player ~= last_player

                                    if needs_text_update then
                                        -- Update album art
                                        album_art.widget.widget.image = art_path

                                        -- Update title and artist with markup for colors
                                        title_widget:set_markup(string.format('<span color="%s">%s</span>',
                                            beautiful.music.title_fg or beautiful.music.fg,
                                            gears.string.xml_escape(clip_text(title, 30))))

                                        artist_widget:set_markup(string.format('<span color="%s">%s</span>',
                                            beautiful.music.artist_fg or beautiful.music.fg,
                                            gears.string.xml_escape(clip_text(artist, 30))))

                                        -- Update player name
                                        if music_widget.current_player then
                                            player_widget:set_markup(string.format('<span color="%s">%s</span>',
                                                beautiful.music.player_fg or beautiful.music.fg .. "88",
                                                gears.string.xml_escape(music_widget.current_player)))
                                        else
                                            player_widget:set_markup("")
                                        end

                                        -- Update play/pause button
                                        if status == "Playing" then
                                            play_pause_button:update_image(icon_dir .. "pause.png")
                                        else
                                            play_pause_button:update_image(icon_dir .. "play.png")
                                        end

                                        -- Store current values for next comparison
                                        last_status = status
                                        last_title = title
                                        last_artist = artist
                                        last_player = music_widget.current_player
                                    end

                                    -- Always update position-related elements
                                    -- Only update progress if playing or significant change
                                    if status == "Playing" or math.abs(music_widget.time - music_widget.last_time) > 1 then
                                        -- Update progress bar
                                        local percent = 0
                                        if length > 0 then
                                            percent = (position / length) * 100
                                        end
                                        progress_bar:set_value(percent)

                                        -- Update time display with markup for colors
                                        local time_text = format_time(position) .. " / " .. format_time(length)
                                        time_display:set_markup(string.format('<span color="%s">%s</span>',
                                            beautiful.music.time_fg or beautiful.music.fg,
                                            gears.string.xml_escape(time_text)))
                                    end

                                    music_widget.last_time = music_widget.time
                                    music_widget.last_update = current_time
                                    music_widget.last_successful_update = current_time
                                    update_in_progress = false
                                end)
                            end)
                        end)
                    end)
                else
                    -- This is just a position update
                    -- Only update progress if playing or significant change
                    if status == "Playing" or math.abs(music_widget.time - music_widget.last_time) > 1 then
                        -- Get cached length
                        local length_str = music_widget.metadata_cache["mpris:length"] and
                                         music_widget.metadata_cache["mpris:length"].value or "0"
                        local length = tonumber(length_str) and (tonumber(length_str) / 1000000) or 0

                        -- Update progress bar
                        local percent = 0
                        if length > 0 then
                            percent = (position / length) * 100
                        end
                        progress_bar:set_value(percent)

                        -- Update time display with markup for colors
                        local time_text = format_time(position) .. " / " .. format_time(length)
                        time_display:set_markup(string.format('<span color="%s">%s</span>',
                            beautiful.music.time_fg or beautiful.music.fg,
                            gears.string.xml_escape(time_text)))
                    end

                    music_widget.last_time = music_widget.time
                    music_widget.last_successful_update = current_time
                    update_in_progress = false
                end
            end)
        end)
    end

    -- Toggle widget visibility
    function music_widget.toggle()
        widget.visible = not widget.visible
        music_widget.visible = widget.visible
        if music_widget.visible then
            music_widget.paused_since = os.time()
        end
        music_widget.update(true)
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

    -- Set up timer callback that handles all updates
    timer:connect_signal("timeout", function()
        local current_time = os.time()

        -- Always update position and status
        music_widget.update(false)

        -- This is now handled within the update function
        -- Check if we need to look for players
        -- if (current_time - music_widget.last_player_check) >= music_widget.player_check_interval then
        --     get_prioritized_player()
        -- end

        return true  -- Keep the timer running
    end)

    -- Initial update (force full update)
    music_widget.update(true)

    widget.forced_width = dpi(400)
    return widget
end

return music_widget