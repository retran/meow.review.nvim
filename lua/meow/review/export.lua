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
-- @file: lua/meow/review/export.lua
-- @brief: Annotation export system with pluggable exporters for AI agent consumption.
-- @author: Andrew Vasilyev
-- @license: MIT

---@mod meow.review.export
---@brief Converts the annotation store to Markdown and dispatches to a registered
---       exporter. Two built-in exporters are provided (file, clipboard). Custom
---       exporters can be registered via `require("meow.review").register_exporter`.
---       When no exporter name is given, the configured `default_exporter` is used
---       (defaults to "clipboard").
local M = {}

-- ── Exporter registry ─────────────────────────────────────────────────────────

---@alias meow.review.ExporterFn fun(markdown: string, root: string)

--- Ordered list of registered exporter names (insertion order).
---@type string[]
local exporter_order = {}

--- Map of exporter name → function.
---@type table<string, meow.review.ExporterFn>
local exporters = {}

--- Register a named exporter function.
--- Replaces any exporter registered under the same name.
--- `fn` receives the Markdown string and the project root path.
---@param name string Unique exporter name (e.g. "file", "clipboard", "zellij")
---@param fn meow.review.ExporterFn
function M.register(name, fn)
    if not exporters[name] then
        table.insert(exporter_order, name)
    end
    exporters[name] = fn
end

--- Unregister a named exporter.
---@param name string
function M.unregister(name)
    exporters[name] = nil
    for i, n in ipairs(exporter_order) do
        if n == name then
            table.remove(exporter_order, i)
            break
        end
    end
end

--- Return the list of currently registered exporter names in insertion order.
---@return string[]
function M.list()
    local result = {}
    for _, name in ipairs(exporter_order) do
        if exporters[name] then
            table.insert(result, name)
        end
    end
    return result
end

-- ── Markdown builder ──────────────────────────────────────────────────────────

-- Map common file extensions to a Markdown code fence language identifier.
local EXT_TO_LANG = {
    lua = "lua",
    py = "python",
    rs = "rust",
    go = "go",
    js = "javascript",
    ts = "typescript",
    tsx = "tsx",
    jsx = "jsx",
    c = "c",
    cpp = "cpp",
    cc = "cpp",
    cxx = "cpp",
    h = "c",
    hpp = "cpp",
    cs = "csharp",
    gd = "gdscript",
    glsl = "glsl",
    vert = "glsl",
    frag = "glsl",
    md = "markdown",
    sh = "bash",
    zsh = "bash",
    fish = "fish",
    vim = "vim",
    json = "json",
    yaml = "yaml",
    toml = "toml",
    html = "html",
    css = "css",
    scss = "scss",
    sql = "sql",
    kt = "kotlin",
    java = "java",
    rb = "ruby",
    swift = "swift",
}

local function fence_lang(file)
    if not file then return "" end
    local ext = file:match("%.([^%.]+)$")
    if not ext then return "" end
    return EXT_TO_LANG[ext:lower()] or ext:lower()
end

local function format_date(ts)
    return os.date("%Y-%m-%d", ts)
end

local function format_location(ann)
    if ann.hunk_head then
        return "hunk " .. ann.hunk_head
    end
    local s = ann.lnum or 1
    local e = ann.end_lnum or s
    if s == e then
        return "line " .. s
    else
        return string.format("lines %d\u{2013}%d", s, e)
    end
end

local function format_heading(ann)
    local loc = format_location(ann)
    -- Include file path in heading for AI agent context
    local base = string.format("### [%s] %s \u{2014} %s", ann.type, ann.file or "?", loc)
    if ann.context and ann.context ~= "" then
        return base .. string.format(" \u{2014} `%s`", ann.context)
    end
    return base
end

local function format_snippet(ann)
    if not ann.snippet or ann.snippet == "" then
        return nil
    end
    local lang = fence_lang(ann.file)
    return string.format("```%s\n%s\n```", lang, ann.snippet)
end

--- Build the full Markdown document from a sorted annotation list.
---
--- The output is structured for AI agent consumption:
--- - Each file gets a `## @file` section so the agent knows which file to edit.
--- - Each annotation has a fenced code snippet with line numbers for precise context.
--- - The heading format `[TYPE] file.lua — line N — symbol` is machine-parseable.
---@param annotations meow.review.Annotation[]
---@param preamble? string Optional preamble override. Uses config value when nil.
---@return string markdown
function M.build_markdown(annotations, preamble)
    if preamble == nil then
        local ok, cfg = pcall(require, "meow.review.config.internal")
        preamble = ok and cfg.get().prompt_preamble or ""
    end

    local lines = {}

    table.insert(lines, string.format("# Code Review \u{2014} %s", format_date(os.time())))
    table.insert(lines, "")
    if preamble and preamble ~= "" then
        table.insert(lines, preamble)
        table.insert(lines, "")
    end

    local current_file = nil
    for _, ann in ipairs(annotations) do
        if ann.file ~= current_file then
            current_file = ann.file
            table.insert(lines, "## @" .. ann.file)
            table.insert(lines, "")
        end

        table.insert(lines, format_heading(ann))
        table.insert(lines, "")

        local snippet_block = format_snippet(ann)
        if snippet_block then
            table.insert(lines, snippet_block)
            table.insert(lines, "")
        end

        table.insert(lines, ann.text or "")
        table.insert(lines, "")
    end

    return table.concat(lines, "\n")
end

-- ── Built-in exporters ────────────────────────────────────────────────────────

--- Built-in: write `.meow-review.md` in the project root.
---@param markdown string
---@param root string
local function export_to_file(markdown, root)
    local path = root .. "/.meow-review.md"
    local f = io.open(path, "w")
    if not f then
        vim.notify("[meow-review] Cannot write " .. path, vim.log.levels.ERROR)
        return
    end
    f:write(markdown)
    f:close()
    vim.notify("[meow-review] Exported \u{2192} .meow-review.md", vim.log.levels.INFO)
end

--- Built-in: copy the Markdown to the system clipboard (+ register).
---@param markdown string
---@param _root string
local function export_to_clipboard(markdown, _root)
    vim.fn.setreg("+", markdown)
    vim.notify("[meow-review] Exported \u{2192} clipboard", vim.log.levels.INFO)
end

-- ── Dispatch ──────────────────────────────────────────────────────────────────

--- Prepare the Markdown from the store and call one named exporter.
--- When {name} is nil, uses the `default_exporter` from config ("clipboard" by default).
--- Emits a warning if the exporter is not registered.
---@param name string|nil Exporter name, or nil to use the configured default.
function M.export(name)
    if not name then
        local ok, cfg = pcall(require, "meow.review.config.internal")
        name = ok and cfg.get().default_exporter or "clipboard"
    end

    local fn = exporters[name]
    if not fn then
        vim.notify("[meow-review] No exporter registered: " .. name, vim.log.levels.WARN)
        return
    end

    local store = require("meow.review.store")
    local sorted = store.sorted()

    if #sorted == 0 then
        vim.notify("[meow-review] No annotations to export.", vim.log.levels.INFO)
        return
    end

    local markdown = M.build_markdown(sorted)
    local root = store.current_root()

    local ok, err = pcall(fn, markdown, root)
    if not ok then
        vim.notify("[meow-review] Exporter '" .. name .. "' failed: " .. tostring(err), vim.log.levels.ERROR)
    end
end

--- Register the built-in exporters based on configuration.
--- Called from `init.lua` during `setup()`.
---@param cfg meow.review.Config
function M.setup_builtins(cfg)
    local disabled = cfg.disabled_exporters or {}
    local disabled_set = {}
    for _, name in ipairs(disabled) do
        disabled_set[name] = true
    end

    if not disabled_set["file"] then
        M.register("file", export_to_file)
    end
    if not disabled_set["clipboard"] then
        M.register("clipboard", export_to_clipboard)
    end
end

return M
