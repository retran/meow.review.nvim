-- MIT License
--
-- Copyright (c) 2025 Andrew Vasilyev <me@retran.me>
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
-- @file: lua/meow/review/ui.lua
-- @brief: nui.nvim multiline modal (add), popup (view), and menu picker (disambiguation).
-- @author: Andrew Vasilyev
-- @license: MIT

---@mod meow.review.ui
local M = {}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function get_types()
    return require("meow.review.types")
end

--- Render the type label shown in the bottom border of the add modal.
--- Shows only the current type: its icon and name.
---@param current_type string
---@return string
local function render_type_line(current_type)
    local types = get_types()
    local t = types.get(current_type)
    local icon = t and t.icon or ""
    local label = t and (t.label or current_type) or current_type
    if icon ~= "" then
        return " " .. icon .. "  " .. label .. " "
    end
    return " " .. label .. " "
end

--- Build the location label for the top border of the add modal.
---@param opts table
---@return string
local function render_location(opts)
    if opts.hunk then
        return " Hunk: " .. opts.hunk.head .. " "
    end
    local s = opts.lnum or 1
    local e = opts.end_lnum or s
    if s == e then
        return string.format(" Line %d ", s)
    else
        return string.format(" Lines %d\u{2013}%d ", s, e)
    end
end

-- ── Add modal ─────────────────────────────────────────────────────────────────

--- Open the add-comment modal (multiline editor).
--- <Tab>    — cycle annotation type
--- <C-s>    — confirm and save (insert or normal mode)
--- <CR>     — confirm and save (normal mode only)
--- <Esc>    — exit insert mode (then <CR>/<C-s> to save, or <Esc>/q to cancel)
--- <C-c>    — cancel immediately
---@param opts table `{ lnum, end_lnum, hunk, context_symbol, file, on_confirm }`
--- `on_confirm(type_name: string, text: string)` is called on confirm.
function M.open_add_modal(opts)
    local Popup = require("nui.popup")
    local event = require("nui.utils.autocmd").event

    local types = get_types()
    local current_type = types.order[1]

    local location_str = render_location(opts)
    local context_str = opts.context_symbol and (" ctx: " .. opts.context_symbol) or ""
    local top_label = " Add Review Comment — " .. location_str:gsub("^ ", ""):gsub(" $", "") .. context_str .. " "

    local popup = Popup({
        position = "50%",
        size = { width = 64, height = 6 },
        enter = true,
        focusable = true,
        border = {
            style = "rounded",
            text = {
                top = top_label,
                top_align = "center",
                bottom = render_type_line(current_type) .. "  <C-s> save · <Tab> type · <C-c> cancel ",
                bottom_align = "left",
            },
        },
        win_options = {
            winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
            wrap = true,
        },
        buf_options = {
            modifiable = true,
            filetype = "markdown",
        },
    })

    popup:mount()

    -- Start in insert mode
    vim.cmd("startinsert")

    local dismissed = false
    local function dismiss()
        if not dismissed then
            dismissed = true
            popup:unmount()
        end
    end

    local function confirm()
        local lines = vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false)
        local text = vim.trim(table.concat(lines, "\n"))
        dismiss()
        if text ~= "" and opts.on_confirm then
            opts.on_confirm(current_type, text)
        end
    end

    -- <C-s>: confirm from insert or normal mode
    popup:map("i", "<C-s>", confirm, { noremap = true })
    popup:map("n", "<C-s>", confirm, { noremap = true })
    -- <CR> in normal mode also confirms (Esc → Enter flow)
    popup:map("n", "<CR>", confirm, { noremap = true })

    -- <Tab> in insert mode: cycle type and update bottom border
    popup:map("i", "<Tab>", function()
        current_type = types.next(current_type)
        popup.border:set_text(
            "bottom",
            render_type_line(current_type) .. "  <C-s> save · <Tab> type · <C-c> cancel "
        )
    end, { noremap = true })

    -- <C-c>: cancel from insert mode
    popup:map("i", "<C-c>", dismiss, { noremap = true })
    -- <Esc> in insert mode: go to normal mode (default Vim behavior — not mapped)
    -- <Esc> / q in normal mode: cancel
    popup:map("n", "<Esc>", dismiss, { noremap = true })
    popup:map("n", "q", dismiss, { noremap = true })

    popup:on(event.BufLeave, function()
        vim.schedule(dismiss)
    end)
end

-- ── Edit modal ────────────────────────────────────────────────────────────────

--- Open the edit-comment modal pre-filled with an existing annotation.
--- Same keybindings as open_add_modal.
---@param annotation meow.review.Annotation
---@param on_confirm fun(type_name: string, text: string)
function M.open_edit_modal(annotation, on_confirm)
    local Popup = require("nui.popup")
    local event = require("nui.utils.autocmd").event

    local types = get_types()
    local current_type = annotation.type or types.order[1]

    local top_label = " Edit Review Comment "

    local popup = Popup({
        position = "50%",
        size = { width = 64, height = 6 },
        enter = true,
        focusable = true,
        border = {
            style = "rounded",
            text = {
                top = top_label,
                top_align = "center",
                bottom = render_type_line(current_type) .. "  <C-s> save · <Tab> type · <C-c> cancel ",
                bottom_align = "left",
            },
        },
        win_options = {
            winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
            wrap = true,
        },
        buf_options = {
            modifiable = true,
            filetype = "markdown",
        },
    })

    popup:mount()

    -- Pre-fill with existing text
    local existing_lines = vim.split(annotation.text or "", "\n", { plain = true })
    vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, existing_lines)

    -- Place cursor at end of last line and enter insert mode
    vim.api.nvim_win_set_cursor(popup.winid, { #existing_lines, #existing_lines[#existing_lines] })
    vim.cmd("startinsert!")

    local dismissed = false
    local function dismiss()
        if not dismissed then
            dismissed = true
            popup:unmount()
        end
    end

    local function confirm()
        local lines = vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false)
        local text = vim.trim(table.concat(lines, "\n"))
        dismiss()
        if text ~= "" then
            on_confirm(current_type, text)
        end
    end

    popup:map("i", "<C-s>", confirm, { noremap = true })
    popup:map("n", "<C-s>", confirm, { noremap = true })
    popup:map("n", "<CR>", confirm, { noremap = true })

    popup:map("i", "<Tab>", function()
        current_type = types.next(current_type)
        popup.border:set_text(
            "bottom",
            render_type_line(current_type) .. "  <C-s> save · <Tab> type · <C-c> cancel "
        )
    end, { noremap = true })

    popup:map("i", "<C-c>", dismiss, { noremap = true })
    popup:map("n", "<Esc>", dismiss, { noremap = true })
    popup:map("n", "q", dismiss, { noremap = true })

    popup:on(event.BufLeave, function()
        vim.schedule(dismiss)
    end)
end

-- ── View popup ────────────────────────────────────────────────────────────────

--- Open a floating popup showing the details of one annotation.
---@param annotation meow.review.Annotation
function M.open_view_popup(annotation)
    local Popup = require("nui.popup")
    local event = require("nui.utils.autocmd").event

    local types = get_types()
    local t = types.get(annotation.type) or {}

    local lines = {}

    -- Location
    local loc
    if annotation.hunk_head then
        loc = "Hunk: " .. annotation.hunk_head
    else
        local s = annotation.lnum
        local e = annotation.end_lnum or s
        loc = s == e and ("Line " .. s) or string.format("Lines %d\u{2013}%d", s, e)
    end
    table.insert(lines, " " .. loc)

    if annotation.context and annotation.context ~= "" then
        table.insert(lines, " Context: " .. annotation.context)
    end

    table.insert(lines, "")

    -- Comment text
    local text = annotation.text or ""
    for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
        table.insert(lines, " " .. line)
    end

    table.insert(lines, "")

    if annotation.timestamp then
        table.insert(lines, " " .. os.date("%Y-%m-%d %H:%M", annotation.timestamp))
    end

    table.insert(lines, "")
    table.insert(lines, " <q>/<Esc> to close")

    local height = math.min(#lines + 2, 20)
    local width = 50
    for _, l in ipairs(lines) do
        if #l + 4 > width then width = #l + 4 end
    end

    local type_label = string.format("[%s] %s", annotation.type, annotation.file or "")

    local popup = Popup({
        position = "50%",
        size = { width = width, height = height },
        enter = true,
        focusable = true,
        border = {
            style = "rounded",
            text = {
                top = " " .. type_label .. " ",
                top_align = "left",
            },
        },
        win_options = {
            winhighlight = "Normal:Normal,FloatBorder:" .. (t.hl or "FloatBorder"),
        },
        buf_options = {
            modifiable = true,
            readonly = false,
        },
    })

    popup:mount()

    vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
    vim.bo[popup.bufnr].modifiable = false

    local function close()
        popup:unmount()
    end

    popup:map("n", "q", close, { noremap = true, nowait = true })
    popup:map("n", "<Esc>", close, { noremap = true, nowait = true })

    popup:on(event.BufLeave, function()
        vim.schedule(close)
    end)
end

-- ── Picker (nui.menu or Snacks fallback) ─────────────────────────────────────

--- Format a single annotation as a display string for the picker.
---@param ann meow.review.Annotation
---@return string
local function format_picker_item(ann)
    local loc
    if ann.hunk_head then
        loc = ann.hunk_head
    elseif (ann.end_lnum or ann.lnum) ~= ann.lnum then
        loc = string.format("%d\u{2013}%d", ann.lnum, ann.end_lnum)
    else
        loc = tostring(ann.lnum)
    end
    local ctx = ann.context and (" \u{2014} " .. ann.context) or ""
    return string.format("[%s] %s:%s%s \u{2014} %s", ann.type, ann.file, loc, ctx, ann.text or "")
end

--- Open a picker over a list of annotations using Snacks (if available) or nui.menu.
--- `title` is shown as the picker/menu heading.
--- `on_select(annotation)` is called with the chosen item.
---@param annotations meow.review.Annotation[]
---@param title string
---@param on_select fun(ann: meow.review.Annotation)
function M.open_picker(annotations, title, on_select)
    if #annotations == 0 then
        vim.notify("[meow-review] No annotations to show.", vim.log.levels.INFO)
        return
    end

    -- Prefer Snacks.picker when available (richer UI with file preview)
    local snacks_ok, Snacks = pcall(require, "snacks")
    if snacks_ok and Snacks and Snacks.picker then
        local store = require("meow.review.store")
        local root = store.current_root()
        local items = {}
        for _, ann in ipairs(annotations) do
            table.insert(items, {
                text = format_picker_item(ann),
                file = (root or "") .. "/" .. (ann.file or ""),
                pos = { ann.lnum or 1, 0 },
                annotation = ann,
            })
        end
        Snacks.picker.pick({
            source = "meow_review",
            title = title or "Review Comments",
            items = items,
            format = "text",
            preview = "file",
            confirm = function(picker, item)
                picker:close()
                if item and item.annotation and on_select then
                    on_select(item.annotation)
                end
            end,
        })
        return
    end

    -- Fallback: nui.menu
    local Menu = require("nui.menu")
    local event = require("nui.utils.autocmd").event

    local menu_items = {}
    for i, ann in ipairs(annotations) do
        table.insert(menu_items, Menu.item(string.format("%d  %s", i, format_picker_item(ann)), { annotation = ann }))
    end

    local menu = Menu({
        position = "50%",
        size = { width = math.min(100, vim.o.columns - 10), height = math.min(#menu_items + 2, 20) },
        border = {
            style = "rounded",
            text = { top = " " .. (title or "Review Comments") .. " ", top_align = "center" },
        },
        win_options = { winhighlight = "Normal:Normal,FloatBorder:FloatBorder" },
    }, {
        lines = menu_items,
        keymap = { focus_next = { "j", "<Down>" }, focus_prev = { "k", "<Up>" }, close = { "q", "<Esc>" }, submit = { "<CR>" } },
        on_submit = function(item)
            if item and item.annotation and on_select then
                on_select(item.annotation)
            end
        end,
    })

    menu:mount()

    menu:on(event.BufLeave, function()
        vim.schedule(function()
            menu:unmount()
        end)
    end)
end

return M
