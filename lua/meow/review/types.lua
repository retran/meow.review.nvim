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

---@type table<string, { icon: string, hl: string, sign_name: string, label: string }>
M.types = {
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

--- Tab-cycling order for the add-comment modal.
---@type string[]
M.order = { "ISSUE", "SUGGESTION", "NOTE" }

--- Register sign definitions and highlight links. Called once from setup().
function M.setup_highlights()
    for _, t in pairs(M.types) do
        vim.fn.sign_define(t.sign_name, {
            text = t.icon,
            texthl = t.hl,
            numhl = "",
        })
    end
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
