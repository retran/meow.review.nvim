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

-- ── Shared modal helper ───────────────────────────────────────────────────────

--- Private helper that creates, mounts, and wires a nui Popup for annotation
--- editing. Both open_add_modal and open_edit_modal delegate here.
---
--- `modal_opts` fields:
---   top_label         string   — text for top border
---   initial_type      string   — starting annotation type key
---   initial_lines     string[] — lines pre-filled into the buffer (empty = blank)
---   cursor_at_end     boolean  — if true place cursor after last char (edit mode)
---   on_confirm        fun(type_name: string, text: string)
---@param modal_opts table
---@return nil
local function open_modal(modal_opts)
    local Popup = require("nui.popup")
    local event = require("nui.utils.autocmd").event

    local types = get_types()
    local current_type = modal_opts.initial_type or types.order[1]

    local cfg = require("meow.review.config.internal").get()
    local modal_width = cfg.modal_width or 64
    local modal_height = cfg.modal_height or 6
    local cycle_key = cfg.modal_cycle_key or "<C-t>"

    local popup = Popup({
        position = "50%",
        size = { width = modal_width, height = modal_height },
        enter = true,
        focusable = true,
        border = {
            style = "rounded",
            text = {
                top = modal_opts.top_label or " Review Comment ",
                top_align = "center",
                bottom = render_type_line(current_type) .. "  [<C-s>] Save  [" .. cycle_key .. "] Type  [<C-c>] Cancel ",
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

    -- Pre-fill buffer when editing an existing annotation
    local initial_lines = modal_opts.initial_lines or {}
    if #initial_lines > 0 then
        vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, initial_lines)
    end

    if modal_opts.cursor_at_end and #initial_lines > 0 then
        local last = initial_lines[#initial_lines]
        vim.api.nvim_win_set_cursor(popup.winid, { #initial_lines, #last })
        vim.cmd("startinsert!")
    else
        vim.cmd("startinsert")
    end

    local dismissed = false
    local function dismiss()
        if not dismissed then
            dismissed = true
            vim.cmd("stopinsert")
            popup:unmount()
        end
    end

    local function confirm()
        local lines = vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false)
        local text = vim.trim(table.concat(lines, "\n"))
        dismiss()
        if text ~= "" and modal_opts.on_confirm then
            modal_opts.on_confirm(current_type, text)
        end
    end

    popup:map("i", "<C-s>", confirm, { noremap = true })
    popup:map("n", "<C-s>", confirm, { noremap = true })
    popup:map("n", "<CR>", confirm, { noremap = true })

    popup:map("i", cycle_key, function()
        current_type = types.next(current_type)
        popup.border:set_text(
            "bottom",
            render_type_line(current_type) .. "  [<C-s>] Save  [" .. cycle_key .. "] Type  [<C-c>] Cancel "
        )
    end, { noremap = true })

    popup:map("i", "<C-c>", dismiss, { noremap = true })
    popup:map("n", "<Esc>", dismiss, { noremap = true })
    popup:map("n", "q", dismiss, { noremap = true })

    popup:on(event.BufLeave, function()
        vim.schedule(dismiss)
    end)
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
    local types = get_types()
    local location_str = render_location(opts)
    local context_str = opts.context_symbol and (" \u{2014} " .. opts.context_symbol) or ""
    local top_label = " Add Review Comment — " .. location_str:gsub("^ ", ""):gsub(" $", "") .. context_str .. " "

    open_modal({
        top_label = top_label,
        initial_type = types.order[1],
        initial_lines = {},
        cursor_at_end = false,
        on_confirm = opts.on_confirm,
    })
end

-- ── Edit modal ────────────────────────────────────────────────────────────────

--- Open the edit-comment modal pre-filled with an existing annotation.
--- Same keybindings as open_add_modal.
---@param annotation meow.review.Annotation
---@param on_confirm fun(type_name: string, text: string)
function M.open_edit_modal(annotation, on_confirm)
    local existing_lines = vim.split(annotation.text or "", "\n", { plain = true })

    -- Build a rich top label: "Edit — file:line [— symbol]"
    local loc_str
    if annotation.hunk_head then
        loc_str = "Hunk: " .. annotation.hunk_head
    else
        local s = annotation.lnum or 1
        local e = annotation.end_lnum or s
        if s == e then
            loc_str = string.format("%s:%d", annotation.file or "", s)
        else
            loc_str = string.format("%s:%d\u{2013}%d", annotation.file or "", s, e)
        end
    end
    local ctx_str = (annotation.context and annotation.context ~= "") and (" \u{2014} " .. annotation.context) or ""
    local top_label = " Edit — " .. loc_str .. ctx_str .. " "

    open_modal({
        top_label = top_label,
        initial_type = annotation.type,
        initial_lines = existing_lines,
        cursor_at_end = true,
        on_confirm = on_confirm,
    })
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

    local height = math.min(#lines + 2, 20)
    local width = 50
    for _, l in ipairs(lines) do
        if #l + 4 > width then width = #l + 4 end
    end

    local type_label = string.format("%s \u{2014} %s", annotation.type, annotation.file or "")

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
                bottom = " [q]/[<Esc>] Close ",
                bottom_align = "left",
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
        vim.notify("MeowReview: No annotations to show.", vim.log.levels.INFO)
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

    -- Second preference: Telescope
    local telescope_ok, telescope = pcall(require, "telescope")
    if telescope_ok and telescope then
        local pickers_ok, pickers = pcall(require, "telescope.pickers")
        local finders_ok, finders = pcall(require, "telescope.finders")
        local conf_ok, conf = pcall(require, "telescope.config")
        local actions_ok, actions = pcall(require, "telescope.actions")
        local action_state_ok, action_state = pcall(require, "telescope.actions.state")

        if pickers_ok and finders_ok and conf_ok and actions_ok and action_state_ok then
            local store = require("meow.review.store")
            local root = store.current_root()
            local entries = {}
            for _, ann in ipairs(annotations) do
                table.insert(entries, {
                    value = ann,
                    display = format_picker_item(ann),
                    ordinal = (ann.file or "") .. ":" .. (ann.lnum or 0) .. " " .. (ann.text or ""),
                    path = root .. "/" .. (ann.file or ""),
                    lnum = ann.lnum or 1,
                })
            end
            pickers
                .new({}, {
                    prompt_title = title or "Review Comments",
                    finder = finders.new_table({
                        results = entries,
                        entry_maker = function(entry) return entry end,
                    }),
                    sorter = conf.values.generic_sorter({}),
                    previewer = conf.values.grep_previewer({}),
                    attach_mappings = function(prompt_bufnr, _map)
                        actions.select_default:replace(function()
                            actions.close(prompt_bufnr)
                            local selection = action_state.get_selected_entry()
                            if selection and selection.value and on_select then
                                on_select(selection.value)
                            end
                        end)
                        return true
                    end,
                })
                :find()
            return
        end
    end

    -- Third preference: fzf-lua
    local fzf_ok, fzf = pcall(require, "fzf-lua")
    if fzf_ok and fzf then
        local store = require("meow.review.store")
        local root = store.current_root()
        local idx_to_ann = {}
        local fzf_items = {}
        for i, ann in ipairs(annotations) do
            idx_to_ann[i] = ann
            table.insert(fzf_items, string.format("%d\t%s", i, format_picker_item(ann)))
        end
        fzf.fzf_exec(fzf_items, {
            prompt = (title or "Review Comments") .. "> ",
            previewer = "builtin",
            fn_transform = function(x) return x end,
            actions = {
                ["default"] = function(selected, _)
                    if not selected or not selected[1] then return end
                    local idx = tonumber(selected[1]:match("^(%d+)\t"))
                    if idx and idx_to_ann[idx] and on_select then
                        on_select(idx_to_ann[idx])
                    end
                end,
            },
            cwd = root,
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
