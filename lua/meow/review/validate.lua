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
-- @file: lua/meow/review/validate.lua
-- @brief: Stale annotation detection for meow.review.nvim
-- @author: Andrew Vasilyev
-- @license: MIT

---@mod meow.review.validate
local M = {}

---@class meow.review.ValidationResult
---@field annotation meow.review.Annotation
---@field stale boolean  True if the annotation is likely stale (file missing or line gone).
---@field reason string  Human-readable reason for staleness, or "ok".

--- Read the lines of a file on disk.
--- Returns nil if the file cannot be opened.
---@param abs_path string
---@return string[]|nil
local function read_lines(abs_path)
    local f = io.open(abs_path, "r")
    if not f then
        return nil
    end
    local lines = {}
    for line in f:lines() do
        table.insert(lines, line)
    end
    f:close()
    return lines
end

--- Check a single annotation against the current file contents.
---@param ann meow.review.Annotation
---@param root string absolute project root
---@return meow.review.ValidationResult
local function check_one(ann, root)
    local abs_path = root .. "/" .. ann.file
    local lines = read_lines(abs_path)

    if not lines then
        return { annotation = ann, stale = true, reason = "file not found: " .. ann.file }
    end

    local lnum = ann.lnum or 1
    if lnum > #lines then
        return {
            annotation = ann,
            stale = true,
            reason = string.format(
                "line %d no longer exists in %s (%d lines total)",
                lnum,
                ann.file,
                #lines
            ),
        }
    end

    -- If the annotation has a snippet, check whether the first snippet line
    -- still roughly matches the current file line (tolerates leading whitespace).
    if ann.snippet and ann.snippet_start then
        local first_snippet_line = ann.snippet:match("^[^\n]*\n?") or ""
        -- Strip the "NNN: " line-number prefix the snippet format adds
        first_snippet_line = first_snippet_line:gsub("^%s*%d+:%s?", "")
        first_snippet_line = vim.trim(first_snippet_line)

        local file_line = vim.trim(lines[ann.snippet_start] or "")

        if first_snippet_line ~= "" and file_line ~= "" and first_snippet_line ~= file_line then
            return {
                annotation = ann,
                stale = true,
                reason = string.format(
                    "%s:%d — content has changed since annotation was added",
                    ann.file,
                    ann.snippet_start
                ),
            }
        end
    end

    return { annotation = ann, stale = false, reason = "ok" }
end

--- Validate all annotations, returning a list of ValidationResult.
--- Annotations whose file exists and whose line is within bounds are marked non-stale.
---@param annotations meow.review.Annotation[]
---@param root string absolute project root
---@return meow.review.ValidationResult[]
function M.check(annotations, root)
    local results = {}
    for _, ann in ipairs(annotations) do
        table.insert(results, check_one(ann, root))
    end
    return results
end

--- Run validation and notify the user of any stale annotations.
--- Stale annotations receive the MeowReviewStale sign highlight in open buffers.
---@param annotations meow.review.Annotation[]
---@param root string
---@return number stale_count
function M.run(annotations, root)
    local results = M.check(annotations, root)
    local stale = {}
    for _, r in ipairs(results) do
        if r.stale then
            table.insert(stale, r)
        end
    end

    if #stale == 0 then
        vim.notify("MeowReview: all annotations are up to date.", vim.log.levels.INFO)
        return 0
    end

    local lines = { string.format("MeowReview: %d stale annotation(s) found:", #stale) }
    for _, r in ipairs(stale) do
        table.insert(lines, string.format("  [%s] %s:%d — %s", r.annotation.type, r.annotation.file, r.annotation.lnum or 0, r.reason))
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.WARN)

    -- Apply MeowReviewStale highlight to signs in open buffers
    local ns = require("meow.review.signs").NS
    local types_mod = require("meow.review.types")
    for _, r in ipairs(stale) do
        local ann = r.annotation
        if ann.bufnr and vim.api.nvim_buf_is_valid(ann.bufnr) and ann.extmark_id then
            local t = types_mod.get(ann.type)
            pcall(vim.api.nvim_buf_set_extmark, ann.bufnr, ns, (ann.lnum or 1) - 1, 0, {
                id = ann.extmark_id,
                sign_text = t and t.icon or "?",
                sign_hl_group = "MeowReviewStale",
            })
        end
    end

    return #stale
end

return M
