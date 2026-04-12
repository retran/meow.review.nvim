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
-- @file: lua/meow/review/context.lua
-- @brief: Treesitter symbol lookup and diff hunk detection at the cursor.
-- @author: Andrew Vasilyev
-- @license: MIT

---@mod meow.review.context
local M = {}

-- ── Treesitter symbol ─────────────────────────────────────────────────────────

-- Node types considered "named contexts" (function / class / method definitions).
local NAMED_CONTEXT_TYPES = {
    -- Lua
    "function_definition",
    "local_function",
    -- Generic / Python
    "method_definition",
    "class_declaration",
    "class_definition",
    "decorated_definition",
    -- Rust
    "function_item",
    "impl_item",
    -- JavaScript / TypeScript
    "arrow_function",
    "lexical_declaration",
    -- Go / C-like
    "function_declaration",
    "method_declaration",
    -- C / C++ / GLSL
    "function_declarator",
    -- C#
    "constructor_declaration",
    "interface_declaration",
    "struct_declaration",
    -- GDScript
    "constructor_definition",
    -- Markdown headings
    "atx_heading",
    "setext_heading",
}

local CONTEXT_TYPE_SET = {}
for _, t in ipairs(NAMED_CONTEXT_TYPES) do
    CONTEXT_TYPE_SET[t] = true
end

--- Try to extract a human-readable name from a Treesitter node.
---@param node table TSNode
---@param src number bufnr
---@return string|nil
local function node_name(node, src)
    local ntype = node:type()

    -- Markdown headings: text lives in the heading_content field
    if ntype == "atx_heading" or ntype == "setext_heading" then
        local content = node:field("heading_content")
        if content and content[1] then
            local text = vim.trim(vim.treesitter.get_node_text(content[1], src))
            return text ~= "" and text or nil
        end
        return nil
    end

    -- Standard named-field lookup
    for _, field in ipairs({ "name", "declarator", "identifier" }) do
        local child = node:field(field)
        if child and child[1] then
            local n = child[1]
            if n:type() == "identifier" or n:type() == "property_identifier" or n:type() == "field_identifier" then
                return vim.treesitter.get_node_text(n, src)
            end
            local inner = n:field("name") or n:field("identifier")
            if inner and inner[1] then
                return vim.treesitter.get_node_text(inner[1], src)
            end
            -- Walk down C-style declarator chain (cap depth to avoid loops)
            local cur = n
            for _ = 1, 5 do
                local decl = cur:field("declarator")
                if decl and decl[1] then
                    cur = decl[1]
                    if cur:type() == "identifier" or cur:type() == "field_identifier" then
                        return vim.treesitter.get_node_text(cur, src)
                    end
                else
                    break
                end
            end
        end
    end
    return nil
end

--- Return the name of the innermost named context (function/class/method) at
--- the current cursor position, or nil if not found / treesitter unavailable.
---@return string|nil
function M.get_symbol()
    local buf = vim.api.nvim_get_current_buf()
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    row = row - 1 -- convert to 0-based

    local node_ok, node = pcall(vim.treesitter.get_node, { bufnr = buf, pos = { row, col } })
    if not node_ok or not node then
        return nil
    end

    local current = node
    while current do
        if CONTEXT_TYPE_SET[current:type()] then
            local name = node_name(current, buf)
            if name and name ~= "" then
                return name
            end
        end
        current = current:parent()
    end

    return nil
end

-- ── Hunk detection ────────────────────────────────────────────────────────────

--- Return the diff hunk enclosing the cursor, or nil.
--- Result: `{ start = N, ["end"] = M, head = "@@ ... @@" }`
---
--- Strategy 1: gitsigns (preferred — works for git-tracked files).
--- Strategy 2: vim.diff fallback for plain `:diffthis` / codediff splits.
---@return { start: number, ["end"]: number, head: string }|nil
function M.find_hunk_at_cursor()
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor_lnum = vim.api.nvim_win_get_cursor(0)[1] -- 1-based

    -- Strategy 1: gitsigns
    local gs_ok, gs = pcall(require, "gitsigns")
    if gs_ok and gs then
        local hunks = gs.get_hunks and gs.get_hunks(bufnr)
        if hunks then
            for _, h in ipairs(hunks) do
                local s = h.added.start
                local count = math.max(h.added.count, 1)
                local e = s + count - 1
                if cursor_lnum >= s and cursor_lnum <= e then
                    return { start = s, ["end"] = e, head = h.head }
                end
            end
        end
    end

    -- Strategy 2: vim.diff fallback for plain :diffthis / codediff
    local cur_win = vim.api.nvim_get_current_win()
    local tab_wins = vim.api.nvim_tabpage_list_wins(0)

    local diff_wins = vim.tbl_filter(function(w)
        return vim.wo[w].diff
    end, tab_wins)

    if #diff_wins < 2 then
        return nil
    end

    local other_win = nil
    for _, w in ipairs(diff_wins) do
        if w ~= cur_win then
            other_win = w
            break
        end
    end

    if not other_win then
        return nil
    end

    local buf_a = vim.api.nvim_win_get_buf(other_win)
    local buf_b = vim.api.nvim_win_get_buf(cur_win)

    local lines_a = vim.api.nvim_buf_get_lines(buf_a, 0, -1, false)
    local lines_b = vim.api.nvim_buf_get_lines(buf_b, 0, -1, false)

    local diff_ok, indices = pcall(vim.diff, table.concat(lines_a, "\n"), table.concat(lines_b, "\n"), {
        result_type = "indices",
        algorithm = "myers",
    })

    if not diff_ok or not indices then
        return nil
    end

    -- indices: { {a_start, a_count, b_start, b_count}, ... } (1-based)
    for _, idx in ipairs(indices) do
        local b_count = idx[4]
        if b_count == 0 then
            goto continue
        end
        local s = idx[3]
        local e = s + b_count - 1
        if cursor_lnum >= s and cursor_lnum <= e then
            return {
                start = s,
                ["end"] = e,
                head = string.format("@@ -%d,%d +%d,%d @@", idx[1], idx[2], idx[3], idx[4]),
            }
        end
        ::continue::
    end

    return nil
end

--- Return true if the current window is in diff mode (vimdiff or :diffthis).
---@return boolean
function M.in_diff_mode()
    return vim.wo.diff == true
end

return M
