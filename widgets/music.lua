-- Simplified Music widget for Awesome WM using playerctl
local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local wibox = require("wibox")
local dpi = require("beautiful.xresources").apply_dpi
local string = require('string')

local config_dir = gears.filesystem.get_configuration_dir()
local icon_dir = config_dir .. "theme-icons/"
local theme = load_util("theme")
local config = require("config")
local naughty = require("naughty")

-- Create album art cache directory
awful.spawn.with_shell("mkdir -p " .. config_dir .. "album_art_cache")

local music_widget = {
    current_player = nil,
    visible = true,
    position = 0,
    status = "Paused",
    player_timeout = config.music_widget_timeout or 60
}

-- Utility function to create playerctl command
local function playerctl_cmd(command)
    if music_widget.current_player then
        return "playerctl --player=" .. music_widget.current_player .. " " .. command
    else
        return "playerctl " .. command
    end
end

-- Format seconds to hours:minutes:seconds
local function format_time(seconds)
    if not seconds or seconds < 0 then return "0:00" end

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local remaining_seconds = math.floor(seconds % 60)

    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, remaining_seconds)
    else
        return string.format("%d:%02d", minutes, remaining_seconds)
    end
end

-- Clip text to a maximum length
local function clip_text(text, max_length)
    if not text then return "" end
    if #text <= max_length then return text end
    return text:sub(1, max_length - 3) .. "..."
end

-- Control functions
function music_widget.play_pause()
    awful.spawn(playerctl_cmd("play-pause"))
    gears.timer.start_new(0.05, function()
        music_widget.update_widget()
    end)
end

function music_widget.next()
    awful.spawn(playerctl_cmd("next"))
    music_widget.update_widget()
end

function music_widget.prev()
    awful.spawn(playerctl_cmd("previous"))
    music_widget.update_widget()
end

-- Create button widget
local function create_button(icon_name, command, tooltip_text)
    local icon_path = icon_dir .. icon_name .. ".png"
    local fallback_text = icon_name == "play" and "▶" or
                         icon_name == "pause" and "⏸" or
                         icon_name == "prev" and "⏮" or
                         icon_name == "next" and "⏭"

    -- Using the existing create_image_button function
    local button = create_image_button({
        image_path = icon_path,
        fallback_text = fallback_text,
        padding = dpi(4),
        button_size = dpi(24),
        opacity = 0.8,
        opacity_hover = 1,
        bg_color = theme.music.button_bg,
        border_color = theme.music.border .. "55",
        shape_radius = dpi(4),
        on_click = command
    })

    return button
end

local recheck_timer = gears.timer({timeout = 2, callback = function()
                          get_player()
                      end})
recheck_timer:start()

-- Get the best player to use based on priorities
function get_player()
    awful.spawn.easy_async_with_shell("playerctl --list-all 2>/dev/null", function(stdout)
        if stdout == "" then
            music_widget.current_player = nil
            return
        end

        -- Get all players
        local players = {}
        for player in string.gmatch(stdout, "[^\r\n]+") do
            table.insert(players, player)
        end

        -- First, check for any playing players
        local playing_player = nil
        for _, player in ipairs(players) do
            awful.spawn.easy_async_with_shell("playerctl --player=" .. player .. " status 2>/dev/null", function(status)
                if status and status:match("^Playing") then
                    if not playing_player then
                        playing_player = player
                        music_widget.current_player = playing_player
                    end
                end
            end)
        end

        -- Keep current player if still active
        for _, player in ipairs(players) do
            if player == music_widget.current_player then
                return
            end
        end

        -- If we found a playing player, use it (will be set in the callbacks above)
        -- Otherwise, continue with priority-based selection

        -- Find player by priority (will only take effect if no playing player was found)
        gears.timer.start_new(0.1, function()  -- Small delay to allow status checks to complete
            if playing_player then return false end  -- Skip if we already found a playing player

            for _, preferred in ipairs(config.music_players or {}) do
                for _, player in ipairs(players) do
                    if string.find(player:lower(), preferred:lower()) then
                        music_widget.current_player = player
                        return false
                    end
                end
            end

            -- Default to first player if no priority match
            if not music_widget.current_player and #players > 0 then
                music_widget.current_player = players[1]
            end

            return false  -- Don't repeat the timer
        end)
    end)
end

-- Create the music widget
function music_widget.create()
    -- Create album art widget
    local album_art = wibox.widget {
        {
            {
                id = "art",
                image = icon_dir .. "music_default.png",
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
            theme.music.title_fg or theme.music.fg,
            "Not playing"),
        font = font_with_size(11),
        widget = wibox.widget.textbox
    }

    local artist_widget = wibox.widget {
        id = "artist",
        markup = "",
        font = font_with_size(10),
        widget = wibox.widget.textbox
    }

    -- Create progress bar
    local progress_bar = wibox.widget {
        id = "progress",
        max_value = 100,
        value = 0,
        forced_height = dpi(3),
        color = theme.music.progress_fg,
        background_color = theme.music.progress_bg,
        widget = wibox.widget.progressbar
    }

    -- Create time display
    local time_display = wibox.widget {
        id = "time",
        markup = string.format('<span color="%s">%s</span>',
            theme.music.time_fg or theme.music.fg,
            "0:00 / 0:00"),
        font = font_with_size(11),
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

    -- Track info container
    local track_info = wibox.widget {
        {
            {
                {
                    title_widget,
                    height = dpi(22),
                    widget = wibox.container.constraint
                },
                artist_widget,
                layout = wibox.layout.fixed.vertical,
                spacing = dpi(2)
            },
            width = dpi(150),
            widget = wibox.container.constraint
        },
        top = dpi(0),
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
                    right = dpi(-8),
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
        width = dpi(210),
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
        bg = theme.music.bg,
        fg = theme.music.fg,
        shape = function(cr, width, height)
            gears.shape.rounded_rect(cr, width, height, dpi(6))
        end,
        shape_border_width = dpi(1),
        shape_border_color = theme.music.border,
        widget = wibox.container.background
    }

    -- Store reference to widget elements
    music_widget.ui = {
        widget = widget,
        album_art = album_art.widget.widget,
        title = title_widget,
        artist = artist_widget,
        progress = progress_bar,
        time = time_display,
        play_pause = play_pause_button
    }

    function music_widget.update_widget()
        -- Check if we have a player
        if not music_widget.current_player then
            get_player()
            widget.visible = false
            return
        end

        -- Single command to get all data at once
        local cmd = string.format([[
                    player='%s'
                    playerctl --player="$player" status 2>/dev/null && echo "---" || exit 1
                    playerctl --player="$player" position 2>/dev/null && echo "---" || echo "0"
                    playerctl --player="$player" metadata xesam:title 2>/dev/null && echo "---" || echo "Unknown"
                    playerctl --player="$player" metadata xesam:artist 2>/dev/null && echo "---" || echo ""
                    playerctl --player="$player" metadata mpris:length 2>/dev/null && echo "---" || echo "0"
                    playerctl --player="$player" metadata mpris:artUrl 2>/dev/null || echo ""
                    ]], music_widget.current_player)

        awful.spawn.easy_async_with_shell(cmd, function(stdout)
            -- Split output by separator
            local parts = {}
            local current_part = ""
            for line in stdout:gmatch("[^\r\n]+") do
                if line == "---" then
                    table.insert(parts, current_part)
                    current_part = ""
                else
                    if current_part ~= "" then
                        current_part = current_part .. "\n" .. line
                    else
                        current_part = line
                    end
                end
            end
            -- Add the last part (artUrl has no separator after it)
            if current_part ~= "" then
                table.insert(parts, current_part)
            end

            -- If we don't have at least the status, player might be gone
            if #parts < 1 or parts[1] == "" then
                music_widget.current_player = nil
                widget.visible = false
                return
            end

            -- Parse all the data
            local status = parts[1] and parts[1]:match("^(.-)%s*$") or "Stopped"
            local position = tonumber(parts[2] and parts[2]:match("^(.-)%s*$")) or 0
            local title = parts[3] and parts[3]:match("^(.-)%s*$") or "Unknown"
            local artist = parts[4] and parts[4]:match("^(.-)%s*$") or ""
            local length = tonumber(parts[5] and parts[5]:match("^(.-)%s*$")) or 0
            length = length / 1000000 -- Convert to seconds
            local art_url = parts[6] and parts[6]:match("^(.-)%s*$") or ""

            music_widget.status = status

            -- Update play/pause button based on status
            if status == "Playing" then
                play_pause_button:update_image(icon_dir .. "pause.png")
                widget.visible = music_widget.visible
                music_widget.last_play_time = os.time()
            else
                play_pause_button:update_image(icon_dir .. "play.png")

                -- Hide widget if paused for too long
                if os.time() - (music_widget.last_play_time or 0) > music_widget.player_timeout then
                    widget.visible = false
                end
            end

            -- Handle album art
            local art_path = icon_dir .. "music_default.png"

            if art_url ~= "" then
                if art_url:sub(1, 7) == "file://" then
                    art_path = art_url:sub(8)
                    music_widget.ui.album_art.image = art_path
                elseif art_url:sub(1, 4) == "http" then
                    -- Generate cache filename
                    awful.spawn.easy_async_with_shell("echo '" .. art_url .. "' | md5sum | cut -d' ' -f1", function(file_hash)
                        file_hash = file_hash:match("^(.-)%s*$")
                        local cache_path = config_dir .. "album_art_cache/" .. file_hash .. ".jpg"

                        -- Download if not cached
                        awful.spawn.easy_async_with_shell("test -f '" .. cache_path .. "' || curl -s -m 5 -o '" .. cache_path .. "' '" .. art_url .. "'", function()
                            music_widget.ui.album_art.image = cache_path
                        end)
                    end)
                else
                    art_path = art_url
                    music_widget.ui.album_art.image = art_path
                end
            else
                music_widget.ui.album_art.image = art_path
            end

            -- Update UI elements
            music_widget.ui.title:set_markup(string.format('<span color="%s">%s</span>',
                theme.music.title_fg or theme.music.fg,
                gears.string.xml_escape(clip_text(title, 30))))

            music_widget.ui.artist:set_markup(string.format('<span color="%s">%s</span>',
                theme.music.artist_fg or theme.music.fg,
                gears.string.xml_escape(clip_text(artist, 30))))

            -- Update progress
            local percent = 0
            if length > 0 then
                percent = (position / length) * 100
            end

            -- Don't update if paused and not skipping
            if not (status == "Paused" and math.abs(music_widget.position - percent) < 1.1) then
                music_widget.position = percent
                -- Update time display
                local time_text = format_time(position) .. " / " .. format_time(length)
                music_widget.ui.time:set_markup(string.format('<span color="%s">%s</span>',
                    theme.music.time_fg or theme.music.fg,
                    gears.string.xml_escape(time_text)))
                music_widget.ui.progress:set_value(percent)
            end
        end)
    end

    -- Toggle widget visibility
    function music_widget.toggle()
        music_widget.visible = not music_widget.visible
        music_widget.ui.widget.visible = music_widget.visible
        if music_widget.visible then
            music_widget.last_play_time = os.time()
            music_widget.update_widget()
        end
    end

    -- Set up a single update timer
    local update_timer = gears.timer({
        timeout = 1,
        autostart = true,
        callback = music_widget.update_widget
    })

    -- Initial update
    get_player()
    music_widget.update_widget()

    widget.width = dpi(400)
    return widget
end

return music_widget