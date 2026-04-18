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
-- @file: lua/meow/review/utils.lua
-- @brief: Shared filesystem utilities for meow.review.nvim.
-- @author: Andrew Vasilyev
-- @license: MIT

---@mod meow.review.utils
local M = {}

--- Resolve a path relative to a root directory.
--- If `path` is already absolute it is returned unchanged.
--- If `path` is relative it is joined to `root` with "/".
---@param path string
---@param root string
---@return string
function M.resolve_path(path, root)
    -- vim.fn.fnamemodify(p, ":p") expands to the absolute form — if it equals p
    -- already then p is already absolute.
    if vim.fn.fnamemodify(path, ":p") == path then
        return path
    end
    return root .. "/" .. path
end

--- Ensure all parent directories of `path` exist, creating them if needed.
---@param path string
function M.ensure_parent_dirs(path)
    local dir = vim.fn.fnamemodify(path, ":h")
    if vim.fn.isdirectory(dir) == 0 then
        vim.fn.mkdir(dir, "p")
    end
end

return M
