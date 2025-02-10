-- Text input widget for AwesomeWM
local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local wibox = require("wibox")
local naughty = require("naughty")
local dpi = require("beautiful.xresources").apply_dpi

local theme = dofile(gears.filesystem.get_configuration_dir() .. "theme.lua")

-- Helper function to find word boundaries
local function find_word_bounds(text, cursor_pos)
    local start_pos = cursor_pos
    local end_pos = cursor_pos
    
    -- Find start of word (move backwards)
    while start_pos > 0 and text:sub(start_pos, start_pos):match("[%w_]") do
        start_pos = start_pos - 1
    end
    start_pos = start_pos + 1
    
    -- Find end of word (move forwards)
    while end_pos <= #text and text:sub(end_pos, end_pos):match("[%w_]") do
        end_pos = end_pos + 1
    end
    end_pos = end_pos - 1
    
    return start_pos, end_pos
end

-- Creates a new text input widget
local function create_text_input(args)
    args = args or {}
    local disable_arrows = args.disable_arrows or false
    local on_text_change = args.on_text_change
    local font = args.font or theme.font
    local forced_height = args.height or dpi(24)
    
    local self = {
        text = "",
        cursor_pos = 0,
        selection_start = nil,
        selection_end = nil,
        cursor_visible = true
    }
    
    -- Create the text widget
    self.text_widget = wibox.widget {
        markup = "",
        align = "left",
        valign = "center",
        font = font,
        forced_height = forced_height,
        widget = wibox.widget.textbox
    }
    
    -- Background for the entire input
    self.background = wibox.widget {
        {
            self.text_widget,
            left = dpi(8),
            right = dpi(8),
            widget = wibox.container.margin
        },
        bg = theme.white .. "00",
        fg = theme.textbox_fg,
        widget = wibox.container.background
    }
    
    -- Update display with cursor and selection
    function self:update_display()
        local displayed_text = self.text
        local markup = ""
        
        -- Handle selection
        if self.selection_start and self.selection_end then
            local start_pos = math.min(self.selection_start, self.selection_end)
            local end_pos = math.max(self.selection_start, self.selection_end)
            
            -- Build markup with selection highlighting
            markup = markup .. "<span background='" .. theme.textbox_fg_selection .. "' foreground='" .. theme.textbox_fg_selected .. "'>"
            markup = markup .. gears.string.xml_escape(displayed_text:sub(start_pos, end_pos))
            markup = markup .. "</span>"
            markup = markup .. gears.string.xml_escape(displayed_text:sub(end_pos + 1))
        else
            markup = gears.string.xml_escape(displayed_text)
        end
        
        -- Add cursor if visible
        if self.cursor_visible then
            local cursor_char = "|"
            if self.cursor_pos == 0 then
                markup = "<span foreground='" .. theme.textbox_fg .. "'>" .. cursor_char .. "</span>" .. markup
            else
                local prefix = markup:sub(1, self.cursor_pos)
                local suffix = markup:sub(self.cursor_pos + 1)
                markup = prefix .. "<span foreground='" .. theme.textbox_fg .. "'>" .. cursor_char .. "</span>" .. suffix
            end
        end
        
        self.text_widget.markup = markup
    end
    
    -- Initialize cursor blink timer
    self.blink_timer = gears.timer {
        timeout = 0.5,
        call_now = true,
        autostart = true,
        callback = function()
            self.cursor_visible = not self.cursor_visible
            self:update_display()
        end
    }
    
    -- Handle text input
    function self:input_char(char)
        -- If there's a selection, remove it first
        if self.selection_start and self.selection_end then
            self:delete_selection()
        end
        
        -- Insert the character at cursor position
        local prefix = self.text:sub(1, self.cursor_pos)
        local suffix = self.text:sub(self.cursor_pos + 1)
        self.text = prefix .. char .. suffix
        self.cursor_pos = self.cursor_pos + 1
        
        if on_text_change then
            on_text_change(self.text)
        end
        
        self:update_display()
    end
    
    -- Handle backspace
    function self:backspace()
        if self.selection_start and self.selection_end then
            self:delete_selection()
        elseif self.cursor_pos > 0 then
            local prefix = self.text:sub(1, self.cursor_pos - 1)
            local suffix = self.text:sub(self.cursor_pos + 1)
            self.text = prefix .. suffix
            self.cursor_pos = self.cursor_pos - 1
            
            if on_text_change then
                on_text_change(self.text)
            end
        end
        self:update_display()
    end
    
    -- Handle delete
    function self:delete()
        if self.selection_start and self.selection_end then
            self:delete_selection()
        elseif self.cursor_pos < #self.text then
            local prefix = self.text:sub(1, self.cursor_pos)
            local suffix = self.text:sub(self.cursor_pos + 2)
            self.text = prefix .. suffix
            
            if on_text_change then
                on_text_change(self.text)
            end
        end
        self:update_display()
    end
    
    -- Move cursor
    function self:move_cursor(direction, ctrl)
        if disable_arrows then return end
        
        if ctrl then
            -- Move by word
            if direction > 0 then
                -- Move to end of current/next word
                local _, word_end = find_word_bounds(self.text, self.cursor_pos + 1)
                self.cursor_pos = word_end or #self.text
            else
                -- Move to start of current/previous word
                local word_start = find_word_bounds(self.text, self.cursor_pos)
                self.cursor_pos = word_start - 1
            end
        else
            -- Move by character
            self.cursor_pos = math.max(0, math.min(#self.text, self.cursor_pos + direction))
        end
        
        -- Clear selection if not holding shift
        self.selection_start = nil
        self.selection_end = nil
        
        -- Reset cursor blink
        self.cursor_visible = true
        self:update_display()
        self.blink_timer:again()
    end
    
    -- Select all text
    function self:select_all()
        self.selection_start = 0
        self.selection_end = #self.text
		self:update_display()
    end
    
    -- Select word at cursor
    function self:select_word()
        if #self.text > 0 then
            self.selection_start, self.selection_end = find_word_bounds(self.text, self.cursor_pos + 1)
            self:update_display()
        end
    end
    
    -- Delete selection
    function self:delete_selection()
        if self.selection_start and self.selection_end then
            local start_pos = math.min(self.selection_start, self.selection_end)
            local end_pos = math.max(self.selection_start, self.selection_end)
            
            self.text = self.text:sub(1, start_pos) .. self.text:sub(end_pos + 1)
            self.selection_start = nil
            self.selection_end = nil
            
            if on_text_change then
                on_text_change(self.text)
            end
            
            self:update_display()
        end
    end
    
    -- Paste from clipboard
    function self:paste()
        -- Get clipboard content using xclip
        awful.spawn.easy_async("xclip -selection clipboard -o", function(stdout)
            if stdout then
                -- Remove any newlines from the clipboard content
                local clipboard_text = stdout:gsub("[\n\r]", "")
                
                -- If there's a selection, remove it first
                if self.selection_start and self.selection_end then
                    self:delete_selection()
                end
                
                -- Insert the clipboard text at cursor position
                local prefix = self.text:sub(1, self.cursor_pos)
                local suffix = self.text:sub(self.cursor_pos + 1)
                self.text = prefix .. clipboard_text .. suffix
                self.cursor_pos = self.cursor_pos + #clipboard_text
                
                if on_text_change then
                    on_text_change(self.text)
                end
                
                self:update_display()
            end
        end)
    end
    
    -- Set up key bindings
    function self:handle_key(mod, key)
        -- Handle Ctrl combinations
        local is_ctrl = false
        for _, m in ipairs(mod) do
            if m == "Control" then
                is_ctrl = true
                break
            end
        end
        
        if is_ctrl then
            if key == "a" then
                self:select_all()
                return true
            elseif key == "v" then
                self:paste()
                return true
            elseif key == "w" then
                self:select_word()
                return true
            elseif key == "Left" and not disable_arrows then
                self:move_cursor(-1, true)
                return true
            elseif key == "Right" and not disable_arrows then
                self:move_cursor(1, true)
                return true
            end
        else
            if key == "Left" and not disable_arrows then
                self:move_cursor(-1, false)
                return true
            elseif key == "Right" and not disable_arrows then
                self:move_cursor(1, false)
                return true
            elseif key == "BackSpace" then
                self:backspace()
                return true
            elseif key == "Delete" then
                self:delete()
                return true
            elseif #key == 1 then
                self:input_char(key)
                return true
            end
        end
        
        return false
    end
    
    -- Method to set text programmatically
    function self:set_text(new_text)
        self.text = new_text or ""
        self.cursor_pos = #self.text
        self.selection_start = nil
        self.selection_end = nil
        self:update_display()
        
        if on_text_change then
            on_text_change(self.text)
        end
    end
    
    -- Do initial display update
    self:update_display()
    
    return self
end

return create_text_input