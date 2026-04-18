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
-- @file: lua/meow/review/init.lua
-- @brief: Public API for meow.review.nvim — AI-assisted code review annotation tool.
-- @author: Andrew Vasilyev
-- @license: MIT

---@mod meow.review
---@brief A Neovim plugin for reviewing AI-generated code and providing structured
---       review comments with code context for AI agents.
---@author Andrew Vasilyev
local M = {}

-- ── Lazy-loaded sub-modules ───────────────────────────────────────────────────

local function store()
    return require("meow.review.store")
end
local function ctx()
    return require("meow.review.context")
end
local function signs()
    return require("meow.review.signs")
end
local function ui()
    return require("meow.review.ui")
end
local function exp()
    return require("meow.review.export")
end

-- ── Exporter API (public, forward to export module) ───────────────────────────

--- Register a named exporter.
--- `fn(markdown, root)` is called with the rendered Markdown and the project root path.
--- Built-in names: "file", "clipboard". Custom names are arbitrary.
---@param name string
---@param fn meow.review.ExporterFn
function M.register_exporter(name, fn)
    exp().register(name, fn)
end

--- Unregister a named exporter.
---@param name string
function M.unregister_exporter(name)
    exp().unregister(name)
end

local function cfg()
    return require("meow.review.config.internal").get()
end

local function types()
    return require("meow.review.types")
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

--- Configure the plugin (optional — safe to call multiple times).
---@param opts meow.review.Config|nil User-provided configuration options.
function M.setup(opts)
    require("meow.review.config.meta")
    vim.g.meow_review = vim.tbl_deep_extend("force", vim.g.meow_review or {}, opts or {})

    -- Initialise annotation type definitions (must run before sign setup)
    local c = cfg()
    types().setup(c.annotation_types, c.annotation_type_order)

    -- Initialise sign definitions and highlight links
    signs().setup_signs()

    -- Register built-in exporters (respects disabled_exporters config)
    exp().setup_builtins(cfg())

    -- Load annotations for the current project root
    local s = store()
    local root = s.get_project_root()
    s.set_project_root(root)
    s.load(root)

    -- Re-render signs when entering a buffer that has annotations.
    -- Debounced 50 ms to avoid redundant work on rapid buffer switches.
    local _bufenter_timer = nil
    vim.api.nvim_create_autocmd("BufEnter", {
        group = vim.api.nvim_create_augroup("MeowReviewBufEnter", { clear = true }),
        callback = function()
            if _bufenter_timer then
                _bufenter_timer:stop()
                _bufenter_timer:close()
                _bufenter_timer = nil
            end
            local bufnr = vim.api.nvim_get_current_buf()
            _bufenter_timer = vim.defer_fn(function()
                _bufenter_timer = nil
                local abs = vim.api.nvim_buf_get_name(bufnr)
                if abs == "" then return end
                local st = store()
                local r = st.current_root()
                local rel = abs:gsub("^" .. vim.pesc(r) .. "/", "")
                if rel == abs then rel = vim.fn.fnamemodify(abs, ":.") end
                if st.has_file(rel) then
                    signs().render_buffer(bufnr)
                end
            end, 50)
        end,
    })

    -- Reload when the working directory changes (multi-project sessions)
    vim.api.nvim_create_autocmd("DirChanged", {
        group = vim.api.nvim_create_augroup("MeowReviewDirChanged", { clear = true }),
        callback = function()
            local st = store()
            local new_root = st.get_project_root()
            if new_root ~= st.current_root() then
                st.set_project_root(new_root)
                st.load(new_root)
            end
        end,
    })
end

-- ── Snippet capture ───────────────────────────────────────────────────────────

--- Read source lines around [lnum, end_lnum] from the current buffer.
--- Returns snippet string and snippet_start (1-based first line), or nil, nil
--- when context_lines == 0.
---@param lnum number
---@param end_lnum number
---@return string|nil snippet
---@return number|nil snippet_start
local function capture_snippet(lnum, end_lnum)
    local pad = cfg().context_lines
    if pad <= 0 then
        return nil, nil
    end

    local bufnr = vim.api.nvim_get_current_buf()
    local total = vim.api.nvim_buf_line_count(bufnr)

    local first = math.max(1, lnum - pad)
    local last = math.min(total, (end_lnum or lnum) + pad)

    local raw = vim.api.nvim_buf_get_lines(bufnr, first - 1, last, false)

    local out = {}
    for i, line in ipairs(raw) do
        table.insert(out, string.format("%d: %s", first + i - 1, line))
    end

    return table.concat(out, "\n"), first
end

-- ── Add comment ───────────────────────────────────────────────────────────────

--- Add a new review annotation at the cursor position or current visual selection.
--- Opens the add-comment modal; Tab cycles ISSUE → SUGGESTION → NOTE.
---@param is_visual? boolean Pass true when called from a visual-mode mapping.
function M.add_comment(is_visual)
    local v_start, v_end

    -- When called from a visual mapping the mode has already reverted to normal,
    -- but the '< and '> marks still hold the last visual selection on this buffer.
    if is_visual then
        v_start = vim.fn.line("'<")
        v_end   = vim.fn.line("'>")
        -- Marks are 0 when never set (fresh buffer) — treat as single-line
        if v_start == 0 then
            v_start = vim.api.nvim_win_get_cursor(0)[1]
            v_end   = v_start
        end
    end

    local cursor_lnum = vim.api.nvim_win_get_cursor(0)[1]
    local context_symbol = ctx().get_symbol()
    local hunk = ctx().find_hunk_at_cursor()

    local lnum, end_lnum
    if v_start then
        lnum = v_start
        end_lnum = v_end
    elseif hunk then
        lnum = hunk.start
        end_lnum = hunk["end"]
    else
        lnum = cursor_lnum
        end_lnum = cursor_lnum
    end

    local file = store().current_file()
    local snippet, snippet_start = capture_snippet(lnum, end_lnum)

    ui().open_add_modal({
        lnum = lnum,
        end_lnum = end_lnum,
        hunk = hunk,
        context_symbol = context_symbol,
        file = file,
        on_confirm = function(type_name, text)
            local ann = {
                file = file,
                lnum = lnum,
                end_lnum = end_lnum,
                type = type_name,
                text = text,
                context = context_symbol,
                snippet = snippet,
                snippet_start = snippet_start,
            }
            if hunk then
                ann.hunk_head = hunk.head
                ann.hunk_start = hunk.start
                ann.hunk_end = hunk["end"]
            end
            local added = store().add(ann)
            local bufnr = vim.api.nvim_get_current_buf()
            signs().place(added, bufnr)
            vim.notify(
                string.format("MeowReview: %s added at %s:%d", type_name, file or "?", lnum),
                vim.log.levels.INFO
            )
        end,
    })
end

-- ── Edit comment ──────────────────────────────────────────────────────────────

--- Edit the annotation at the cursor position.
--- When multiple annotations overlap the cursor, opens a picker to choose.
function M.edit_comment()
    local candidates = store().get_at_cursor()

    if #candidates == 0 then
        vim.notify("MeowReview: No comment at cursor.", vim.log.levels.WARN)
        return
    end

    local function do_edit(ann)
        ui().open_edit_modal(ann, function(type_name, text)
            store().update(ann.id, { type = type_name, text = text })
            vim.notify("MeowReview: Comment updated.", vim.log.levels.INFO)
        end)
    end

    if #candidates == 1 then
        do_edit(candidates[1])
        return
    end

    ui().open_picker(candidates, "Edit Comment", do_edit)
end

-- ── Delete comment ────────────────────────────────────────────────────────────

--- Delete the annotation at the cursor position.
--- When multiple annotations overlap the cursor, opens a picker to choose.
function M.delete_comment()
    local candidates = store().get_at_cursor()

    if #candidates == 0 then
        vim.notify("MeowReview: No comment at cursor.", vim.log.levels.WARN)
        return
    end

    if #candidates == 1 then
        store().delete(candidates[1].id)
        vim.notify("MeowReview: Comment deleted.", vim.log.levels.INFO)
        return
    end

    ui().open_picker(candidates, "Delete Comment", function(ann)
        store().delete(ann.id)
        vim.notify("MeowReview: Comment deleted.", vim.log.levels.INFO)
    end)
end

-- ── View comment ──────────────────────────────────────────────────────────────

--- View the annotation at the cursor position in a floating popup.
function M.view_comment()
    local candidates = store().get_at_cursor()

    if #candidates == 0 then
        vim.notify("MeowReview: No comment at cursor.", vim.log.levels.WARN)
        return
    end

    if #candidates == 1 then
        ui().open_view_popup(candidates[1])
        return
    end

    ui().open_picker(candidates, "View Comment", function(ann)
        ui().open_view_popup(ann)
    end)
end

-- ── Export ────────────────────────────────────────────────────────────────────

--- Export annotations using a named exporter.
--- When {name} is nil, the configured `default_exporter` is used ("clipboard" by default).
--- Built-in names: "file", "clipboard". Custom exporters registered via register_exporter().
---@param name string|nil Exporter name, or nil to use the configured default.
function M.export_review(name)
    exp().export(name)
end

-- ── Clear all ─────────────────────────────────────────────────────────────────

--- Prompt to remove all annotations and clear all signs.
function M.clear_all()
    local n = store().count()
    if n == 0 then
        vim.notify("MeowReview: No annotations.", vim.log.levels.INFO)
        return
    end
    vim.ui.select(
        { "Yes, clear all", "Cancel" },
        { prompt = string.format("Clear all %d annotation(s)?", n) },
        function(choice)
            if choice == "Yes, clear all" then
                store().clear()
                signs().render_all()
                vim.notify("MeowReview: All comments cleared.", vim.log.levels.INFO)
            end
        end
    )
end

-- ── Go to comment picker ──────────────────────────────────────────────────────

--- Open a picker listing all annotations; selecting one jumps to its location.
function M.goto_comment()
    local all = store().sorted()
    if #all == 0 then
        vim.notify("MeowReview: No annotations.", vim.log.levels.INFO)
        return
    end
    ui().open_picker(all, "Go to Comment", function(ann)
        M._jump_to(ann)
    end)
end

-- ── Reload ────────────────────────────────────────────────────────────────────

--- Reload annotations from `.meow-review.json` and re-render all signs.
function M.reload()
    local root = store().get_project_root()
    store().load(root)
    signs().render_all()
    vim.notify(
        string.format("MeowReview: Reloaded %d comment(s).", store().count()),
        vim.log.levels.INFO
    )
end

-- ── Navigation ────────────────────────────────────────────────────────────────

--- Internal: jump to an annotation, opening its file if needed.
---@param ann meow.review.Annotation
---@return boolean jumped
function M._jump_to(ann)
    local s = store()
    local root = s.current_root()
    local abs_path = root .. "/" .. ann.file

    if vim.fn.filereadable(abs_path) == 0 then
        vim.notify(
            string.format("MeowReview: File no longer exists: %s", ann.file),
            vim.log.levels.WARN
        )
        return false
    end

    local cur_abs = vim.api.nvim_buf_get_name(0)
    if cur_abs ~= abs_path then
        vim.cmd.edit(abs_path)
    end

    vim.api.nvim_win_set_cursor(0, { ann.lnum, 0 })
    return true
end

--- Jump to the next annotation in sorted order (wraps around).
function M.next_comment()
    local s = store()
    local file = s.current_file() or ""
    local lnum = vim.api.nvim_win_get_cursor(0)[1]

    local sorted = s.sorted()
    if #sorted == 0 then
        vim.notify("MeowReview: No annotations.", vim.log.levels.INFO)
        return
    end

    local ann = s.find_next(file, lnum)
    if not ann then
        vim.notify("MeowReview: No next comment.", vim.log.levels.INFO)
        return
    end

    local visited = {}
    while ann do
        if visited[ann.id] then
            vim.notify("MeowReview: All annotation files are unreadable.", vim.log.levels.WARN)
            return
        end
        visited[ann.id] = true
        if M._jump_to(ann) then return end
        ann = s.find_next(ann.file, ann.lnum + 1)
    end
end

--- Jump to the previous annotation in sorted order (wraps around).
function M.prev_comment()
    local s = store()
    local file = s.current_file() or ""
    local lnum = vim.api.nvim_win_get_cursor(0)[1]

    local sorted = s.sorted()
    if #sorted == 0 then
        vim.notify("MeowReview: No annotations.", vim.log.levels.INFO)
        return
    end

    local ann = s.find_prev(file, lnum)
    if not ann then
        vim.notify("MeowReview: No previous comment.", vim.log.levels.INFO)
        return
    end

    local visited = {}
    while ann do
        if visited[ann.id] then
            vim.notify("MeowReview: All annotation files are unreadable.", vim.log.levels.WARN)
            return
        end
        visited[ann.id] = true
        if M._jump_to(ann) then return end
        ann = s.find_prev(ann.file, ann.lnum - 1)
    end
end

-- ── Status ────────────────────────────────────────────────────────────────────

--- Return a compact status string suitable for embedding in a statusline.
--- Format: "" when there are no annotations, or "  N" when there are N
--- annotations, optionally with a per-type breakdown "(Xa Yb …)" when types
--- differ.
--- Example: "  3 (2 ISSUE 1 NOTE)"
---@return string
function M.status()
    local s = store()
    local n = s.count()
    if n == 0 then
        return ""
    end

    -- Count per type
    local counts = {}
    local type_order = {}
    for _, ann in ipairs(s.sorted()) do
        local t = ann.type or "?"
        if not counts[t] then
            counts[t] = 0
            table.insert(type_order, t)
        end
        counts[t] = counts[t] + 1
    end

    -- Build type breakdown if more than one type present
    local detail = ""
    if #type_order > 1 then
        local parts = {}
        for _, t in ipairs(type_order) do
            table.insert(parts, counts[t] .. " " .. t)
        end
        detail = " (" .. table.concat(parts, ", ") .. ")"
    end

    return "  " .. n .. detail
end

--- Run stale annotation detection and notify the user.
--- Stale annotations (file missing or line out of range) are highlighted with
--- the MeowReviewStale sign group. Returns the number of stale annotations found.
---@return number
function M.validate()
    local s = store()
    local root = s.current_root()
    return require("meow.review.validate").run(s.all(), root)
end

return M
