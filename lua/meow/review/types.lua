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
-- @file: lua/meow/review/types.lua
-- @brief: Annotation type definitions, icons, and highlight groups.
-- @author: Andrew Vasilyev
-- @license: MIT

---@mod meow.review.types
local M = {}

--- Default annotation type definitions.
---@type table<string, { icon: string, hl: string, sign_name: string, label: string }>
local DEFAULT_TYPES = {
    ISSUE = {
        icon = "",
        hl = "DiagnosticError",
        sign_name = "MeowReviewIssue",
        label = "ISSUE",
    },
    SUGGESTION = {
        icon = "",
        hl = "DiagnosticWarn",
        sign_name = "MeowReviewSuggestion",
        label = "SUGGESTION",
    },
    NOTE = {
        icon = "",
        hl = "DiagnosticInfo",
        sign_name = "MeowReviewNote",
        label = "NOTE",
    },
}

--- Default tab-cycling order.
---@type string[]
local DEFAULT_ORDER = { "ISSUE", "SUGGESTION", "NOTE" }

--- Active type definitions (set by setup()).
---@type table<string, { icon: string, hl: string, sign_name: string, label: string }>
M.types = vim.deepcopy(DEFAULT_TYPES)

--- Active tab-cycling order (set by setup()).
---@type string[]
M.order = vim.deepcopy(DEFAULT_ORDER)

--- Initialise annotation types from configuration.
--- Called once from `init.lua` during `setup()`.
---
--- Each entry in {cfg_types} is a table:
---   { icon = "…", hl = "HighlightGroup", label = "NAME" }
---
--- The key is the type name used in annotations (e.g. "ISSUE").
--- `sign_name` is derived automatically as "MeowReview" .. key if not provided.
--- `order` controls the Tab-cycling sequence; defaults to sorted keys if omitted.
---@param cfg_types? table<string, { icon?: string, hl?: string, label?: string, sign_name?: string }>
---@param order? string[]
function M.setup(cfg_types, order)
    if not cfg_types or vim.tbl_isempty(cfg_types) then
        -- Restore defaults (handles repeated setup() calls)
        M.types = vim.deepcopy(DEFAULT_TYPES)
        M.order = vim.deepcopy(DEFAULT_ORDER)
        return
    end

    -- Build type table: merge each user entry over its default (if any).
    local resolved = {}
    for key, def in pairs(cfg_types) do
        local default = DEFAULT_TYPES[key] or {}
        resolved[key] = {
            icon = def.icon or default.icon or "",
            hl = def.hl or default.hl or "Normal",
            label = def.label or default.label or key,
            sign_name = def.sign_name or default.sign_name or ("MeowReview" .. key),
        }
    end
    M.types = resolved

    -- Build order: use provided order, falling back to sorted keys.
    if order and #order > 0 then
        M.order = order
    else
        local keys = vim.tbl_keys(resolved)
        table.sort(keys)
        M.order = keys
    end
end

--- Register highlight groups for all active annotation types.
--- Called once from setup() via signs.setup_signs().
function M.setup_highlights()
    -- Resolved: dimmed, neutral tone.
    vim.api.nvim_set_hl(0, "MeowReviewResolved", { link = "Comment", default = true })
    -- Stale: warn-level, indicates the annotated code has changed.
    vim.api.nvim_set_hl(0, "MeowReviewStale", { link = "DiagnosticWarn", default = true })
end

--- Return the type definition table for a given type string, or nil.
---@param type_name string
---@return { icon: string, hl: string, sign_name: string, label: string }|nil
function M.get(type_name)
    return M.types[type_name]
end

--- Return the next type in cycling order after the given type string.
---@param type_name string
---@return string
function M.next(type_name)
    for i, name in ipairs(M.order) do
        if name == type_name then
            local next_idx = (i % #M.order) + 1
            return M.order[next_idx]
        end
    end
    return M.order[1]
end

return M
