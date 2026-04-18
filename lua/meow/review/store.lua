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
-- @file: lua/meow/review/store.lua
-- @brief: Annotation state management, JSON persistence, and project root detection.
-- @author: Andrew Vasilyev
-- @license: MIT

---@mod meow.review.store
local M = {}

-- Runtime state (not serialised to disk)
---@class meow.review.State
---@field annotations meow.review.Annotation[]
---@field project_root string|nil
local state = {
    annotations = {},
    project_root = nil,
}

-- Seed the PRNG once at module load time.
-- Prefer vim.uv (Nvim 0.10+) for nanosecond precision; fall back to luv then os.time().
do
    local uv = vim.uv or (pcall(require, "luv") and require("luv")) or nil
    if uv and uv.hrtime then
        math.randomseed(uv.hrtime())
    else
        math.randomseed(os.time())
    end
end

--- Signs module, required lazily to avoid circular dependency.
local function get_signs()
    return require("meow.review.signs")
end

-- ── Project root ──────────────────────────────────────────────────────────────

--- Resolve the project root for the given directory (or current buffer dir).
--- Uses `git rev-parse`; falls back to cwd.
---@param dir string|nil
---@return string
function M.get_project_root(dir)
    dir = dir or vim.fn.expand("%:p:h")
    if dir == "" then
        dir = vim.fn.getcwd()
    end

    -- Prefer the no-shell table form (Nvim 0.10+) to avoid any injection risk.
    if vim.system then
        local result = vim.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" }, { text = true }):wait()
        if result.code == 0 and result.stdout and result.stdout ~= "" then
            return vim.trim(result.stdout)
        end
    else
        local result = vim.fn.system("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel 2>/dev/null")
        if vim.v.shell_error == 0 and result ~= "" then
            return vim.trim(result)
        end
    end

    return vim.fn.getcwd()
end

--- Return the cached project root, computing it on first call.
---@return string
function M.current_root()
    if not state.project_root then
        state.project_root = M.get_project_root()
    end
    return state.project_root
end

--- Update the cached project root (called from DirChanged autocmd).
---@param root string
function M.set_project_root(root)
    state.project_root = root
end

-- ── Persistence ───────────────────────────────────────────────────────────────

local VERSION = 1

--- Resolve the absolute path to the annotation store file.
--- The configured `store_path` may be relative (resolved against the project root)
--- or absolute. Parent directories are created automatically on first write.
---@param root string
---@return string
local function resolve_store_path(root)
    local cfg = require("meow.review.config.internal").get()
    local utils = require("meow.review.utils")
    return utils.resolve_path(cfg.store_path, root)
end

--- Return the absolute path to the annotation store file for the given
--- (or current) project root. Useful for health checks and tooling.
---@param root string|nil
---@return string
function M.get_store_path(root)
    return resolve_store_path(root or M.current_root())
end

--- Ensure all parent directories of `path` exist.
---@param path string
local function ensure_parent_dirs(path)
    require("meow.review.utils").ensure_parent_dirs(path)
end

-- Fields that are serialised to disk (runtime tracking fields excluded).
local SERIAL_FIELDS = {
    "id",
    "file",
    "lnum",
    "end_lnum",
    "hunk_head",
    "hunk_start",
    "hunk_end",
    "type",
    "text",
    "context",
    "timestamp",
    "snippet",
    "snippet_start",
    "resolved",
}

local function annotation_to_json(ann)
    local t = {}
    for _, k in ipairs(SERIAL_FIELDS) do
        t[k] = ann[k]
    end
    return t
end

-- ── Gitignore management ──────────────────────────────────────────────────────

--- Check if the given pattern is already in the given .gitignore file.
---@param gitignore_path string absolute path to the .gitignore file
---@param pattern string gitignore pattern to look for
---@return boolean
local function is_in_gitignore(gitignore_path, pattern)
    local f = io.open(gitignore_path, "r")
    if not f then
        return false
    end
    for line in f:lines() do
        if vim.trim(line) == pattern then
            f:close()
            return true
        end
    end
    f:close()
    return false
end

--- Append a pattern to the .gitignore in the given root.
---@param root string project root
---@param pattern string gitignore pattern to append
local function append_to_gitignore(root, pattern)
    local gitignore_path = root .. "/.gitignore"
    local f = io.open(gitignore_path, "a")
    if not f then
        vim.notify("MeowReview: Cannot write .gitignore at " .. gitignore_path, vim.log.levels.WARN)
        return
    end
    f:write("\n# meow.review annotation store\n" .. pattern .. "\n")
    f:close()
    vim.notify("MeowReview: Added '" .. pattern .. "' to .gitignore", vim.log.levels.INFO)
end

--- Derive the shortest gitignore pattern for a store path relative to a root.
---@param store_path string absolute path to the store file
---@param root string absolute project root
---@return string
local function gitignore_pattern(store_path, root)
    local rel = store_path:gsub("^" .. vim.pesc(root) .. "/", "")
    if rel ~= store_path then
        -- relative — prefix with / to anchor to root
        return "/" .. rel
    end
    -- outside root: use the basename as best effort
    return "/" .. vim.fn.fnamemodify(store_path, ":t")
end

--- Handle auto-gitignore logic after saving.
---@param root string
---@param path string absolute store path
local function handle_auto_gitignore(root, path)
    local cfg = require("meow.review.config.internal").get()
    local setting = cfg.auto_gitignore

    if setting == false then
        return
    end

    local gitignore_path = root .. "/.gitignore"
    local pattern = gitignore_pattern(path, root)

    if is_in_gitignore(gitignore_path, pattern) then
        return -- already ignored
    end

    if setting == "always" then
        append_to_gitignore(root, pattern)
    elseif setting == "prompt" then
        vim.ui.select(
            { "Add to .gitignore (recommended)", "Dismiss" },
            { prompt = "MeowReview: annotation store is not in .gitignore:" },
            function(choice)
                if choice and choice:find("Add") then
                    append_to_gitignore(root, pattern)
                end
            end
        )
    end
end

-- ── Persistence helpers ───────────────────────────────────────────────────────

--- Sync open-buffer extmark positions back into annotation lnums before saving.
local function sync_extmark_positions()
    local ns = require("meow.review.signs").NS
    for _, ann in ipairs(state.annotations) do
        if ann.extmark_id and ann.bufnr and vim.api.nvim_buf_is_valid(ann.bufnr) then
            local pos = vim.api.nvim_buf_get_extmark_by_id(ann.bufnr, ns, ann.extmark_id, {})
            if pos and pos[1] then
                ann.lnum = pos[1] + 1 -- extmarks are 0-based
            end
        end
    end
end

--- Write all annotations to the configured store path under the project root.
function M.save()
    sync_extmark_positions()

    local root = M.current_root()
    local path = resolve_store_path(root)
    ensure_parent_dirs(path)

    local data = {
        version = VERSION,
        annotations = vim.tbl_map(annotation_to_json, state.annotations),
    }

    local ok, json = pcall(vim.json.encode, data)
    if not ok then
        vim.notify("MeowReview: Failed to encode annotations: " .. tostring(json), vim.log.levels.ERROR)
        return
    end

    local f = io.open(path, "w")
    if not f then
        vim.notify("MeowReview: Cannot write " .. path, vim.log.levels.ERROR)
        return
    end
    f:write(json)
    f:close()

    -- After a successful write, handle gitignore (non-blocking if prompt)
    vim.schedule(function()
        handle_auto_gitignore(root, path)
    end)
end

--- Load annotations from the configured store path in the given (or current) root.
---@param root string|nil
function M.load(root)
    root = root or M.current_root()
    state.project_root = root

    local path = resolve_store_path(root)
    local f = io.open(path, "r")
    if not f then
        state.annotations = {}
        return
    end

    local raw = f:read("*a")
    f:close()

    local ok, data = pcall(vim.json.decode, raw)
    if not ok or type(data) ~= "table" then
        vim.notify("MeowReview: Cannot parse " .. path, vim.log.levels.WARN)
        state.annotations = {}
        return
    end

    if data.version ~= VERSION then
        vim.notify("MeowReview: Unsupported version in " .. path, vim.log.levels.WARN)
        state.annotations = {}
        return
    end

    state.annotations = {}
    for _, ann in ipairs(data.annotations or {}) do
        if ann.id and ann.file and ann.lnum and ann.type and ann.text then
            ann.extmark_id = nil
            ann.bufnr = nil
            if ann.resolved == nil then
                ann.resolved = false
            end
            table.insert(state.annotations, ann)
        end
    end

    -- Re-render signs in already-open buffers after the event loop settles
    vim.schedule(function()
        get_signs().render_all()
    end)
end

--- Generate a collision-resistant unique ID.
--- Uses `vim.uv.hrtime()` (nanosecond monotonic clock) combined with a random
--- suffix to make simultaneous add() calls within the same millisecond safe.
local function make_id()
    local uv = vim.uv or (pcall(require, "luv") and require("luv")) or nil
    local ts = (uv and uv.hrtime) and uv.hrtime() or (os.time() * 1e9)
    return string.format("%d_%d", ts, math.random(100000, 999999))
end

-- ── CRUD ──────────────────────────────────────────────────────────────────────

--- Add an annotation and persist to disk.
---@param annotation meow.review.Annotation
---@return meow.review.Annotation annotation with id and timestamp filled in
function M.add(annotation)
    annotation.id = make_id()
    annotation.timestamp = annotation.timestamp or os.time()
    if annotation.resolved == nil then
        annotation.resolved = false
    end
    table.insert(state.annotations, annotation)
    M.save()
    return annotation
end

--- Delete an annotation by id, removing its sign/extmark if the buffer is open.
---@param id string
---@return boolean deleted
function M.delete(id)
    local signs = get_signs()
    for i, ann in ipairs(state.annotations) do
        if ann.id == id then
            if ann.bufnr and vim.api.nvim_buf_is_valid(ann.bufnr) then
                signs.unplace(ann, ann.bufnr)
            end
            table.remove(state.annotations, i)
            M.save()
            return true
        end
    end
    return false
end

--- Update text and/or type of an annotation by id. Re-renders the sign in place.
---@param id string
---@param fields { text?: string, type?: string }
---@return boolean updated
function M.update(id, fields)
    local signs = get_signs()
    for _, ann in ipairs(state.annotations) do
        if ann.id == id then
            if fields.text ~= nil then
                ann.text = fields.text
            end
            if fields.type ~= nil then
                ann.type = fields.type
            end
            ann.timestamp = os.time()
            -- Re-render sign (type icon/colour may have changed)
            if ann.bufnr and vim.api.nvim_buf_is_valid(ann.bufnr) then
                signs.place(ann, ann.bufnr)
            end
            M.save()
            return true
        end
    end
    return false
end

--- Mark an annotation as resolved by id. Saves to disk.
---@param id string
---@return boolean resolved
function M.resolve(id)
    for _, ann in ipairs(state.annotations) do
        if ann.id == id then
            ann.resolved = true
            M.save()
            return true
        end
    end
    return false
end

--- Mark all annotations as resolved. Saves to disk.
function M.resolve_all()
    for _, ann in ipairs(state.annotations) do
        ann.resolved = true
    end
    M.save()
end

--- Remove all annotations and clear all signs/extmarks from every loaded buffer.
function M.clear()
    local signs = get_signs()
    for _, ann in ipairs(state.annotations) do
        if ann.bufnr and vim.api.nvim_buf_is_valid(ann.bufnr) then
            signs.unplace(ann, ann.bufnr)
        end
    end
    -- Sweep every loaded buffer unconditionally (some annotations may not be rendered yet)
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            pcall(vim.api.nvim_buf_clear_namespace, bufnr, signs.NS, 0, -1)
        end
    end
    state.annotations = {}
    M.save()
end

-- ── Queries ───────────────────────────────────────────────────────────────────

--- Return the raw annotations list (do not mutate).
---@return meow.review.Annotation[]
function M.all()
    return state.annotations
end

--- Return the number of annotations.
---@return number
function M.count()
    return #state.annotations
end

--- Return true if any annotation references the given relative file path.
---@param rel_path string
---@return boolean
function M.has_file(rel_path)
    for _, ann in ipairs(state.annotations) do
        if ann.file == rel_path then
            return true
        end
    end
    return false
end

--- Return the relative file path of the current buffer (relative to project root).
---@return string|nil
function M.current_file()
    local abs = vim.api.nvim_buf_get_name(0)
    if abs == "" then
        return nil
    end
    local root = M.current_root()
    local rel = abs:gsub("^" .. vim.pesc(root) .. "/", "")
    if rel == abs then
        rel = vim.fn.fnamemodify(abs, ":.")
    end
    return rel
end

--- Return all annotations whose range covers cursor_lnum in the given file.
---@param rel_path string
---@param cursor_lnum number
---@return meow.review.Annotation[]
function M.get_at_line(rel_path, cursor_lnum)
    local result = {}
    for _, ann in ipairs(state.annotations) do
        if ann.file == rel_path then
            local s = ann.hunk_start or ann.lnum
            local e = ann.hunk_end or ann.end_lnum or ann.lnum
            if cursor_lnum >= s and cursor_lnum <= e then
                table.insert(result, ann)
            end
        end
    end
    return result
end

--- Return annotations at the current cursor position.
---@return meow.review.Annotation[]
function M.get_at_cursor()
    local rel = M.current_file()
    if not rel then
        return {}
    end
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    return M.get_at_line(rel, lnum)
end

--- Return all annotations sorted by file then lnum.
--- By default, resolved annotations are excluded.
---@param opts? { include_resolved?: boolean }
---@return meow.review.Annotation[]
function M.sorted(opts)
    opts = opts or {}
    local include_resolved = opts.include_resolved == true
    local copy = {}
    for _, ann in ipairs(state.annotations) do
        if include_resolved or not ann.resolved then
            table.insert(copy, vim.deepcopy(ann))
        end
    end
    table.sort(copy, function(a, b)
        if a.file ~= b.file then
            return a.file < b.file
        end
        return (a.lnum or 0) < (b.lnum or 0)
    end)
    return copy
end

--- Find the next annotation after {file, lnum} in sorted order (wraps around).
---@param file string
---@param lnum number
---@return meow.review.Annotation|nil
function M.find_next(file, lnum)
    file = file or ""
    local sorted = M.sorted()
    if #sorted == 0 then
        return nil
    end
    for _, ann in ipairs(sorted) do
        local af = ann.file or ""
        if af > file or (af == file and (ann.lnum or 0) > lnum) then
            return ann
        end
    end
    return sorted[1] -- wrap
end

--- Find the previous annotation before {file, lnum} in sorted order (wraps around).
---@param file string
---@param lnum number
---@return meow.review.Annotation|nil
function M.find_prev(file, lnum)
    file = file or ""
    local sorted = M.sorted()
    if #sorted == 0 then
        return nil
    end
    for i = #sorted, 1, -1 do
        local ann = sorted[i]
        local af = ann.file or ""
        if af < file or (af == file and (ann.lnum or 0) < lnum) then
            return ann
        end
    end
    return sorted[#sorted] -- wrap
end

return M
