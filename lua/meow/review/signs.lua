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
-- @file: lua/meow/review/signs.lua
-- @brief: Sign column placement via extmark sign_text API (Neovim 0.10+).
-- @author: Andrew Vasilyev
-- @license: MIT

---@mod meow.review.signs
local M = {}

--- Extmark namespace for all signs and position drift tracking.
M.NS = vim.api.nvim_create_namespace("meow_review")

--- Register highlight groups. Called once from init.lua setup().
function M.setup_signs()
    require("meow.review.types").setup_highlights()
end

--- Place a sign and a tracking extmark for one annotation in bufnr.
--- Uses nvim_buf_set_extmark with sign_text/sign_hl_group (Neovim 0.10+).
--- Populates annotation.extmark_id and annotation.bufnr (runtime fields).
---@param annotation meow.review.Annotation
---@param bufnr number
function M.place(annotation, bufnr)
    local types = require("meow.review.types")
    local t = types.get(annotation.type)
    if not t then
        return
    end

    -- Ensure sign column is visible in every window showing this buffer
    for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
        local sc = vim.wo[win].signcolumn
        if sc == "no" or sc == "" then
            vim.wo[win].signcolumn = "yes"
        end
    end

    -- Determine effective highlight: resolved > stale > normal type hl.
    local sign_hl
    if annotation.resolved then
        sign_hl = "MeowReviewResolved"
    elseif annotation.stale then
        sign_hl = "MeowReviewStale"
    else
        sign_hl = t.hl
    end

    -- Place extmark with sign_text/sign_hl_group.
    -- col=-1 is the canonical column for sign extmarks (no position conflict with text extmarks).
    local ok, extmark_id = pcall(vim.api.nvim_buf_set_extmark, bufnr, M.NS, annotation.lnum - 1, -1, {
        id = annotation.extmark_id or nil, -- reuse id when re-placing
        sign_text = t.icon,
        sign_hl_group = sign_hl,
        priority = 5,
    })

    if ok then
        annotation.extmark_id = extmark_id
        annotation.bufnr = bufnr
    end
end

--- Remove extmark (sign + tracker) for one annotation from bufnr.
---@param annotation meow.review.Annotation
---@param bufnr number
function M.unplace(annotation, bufnr)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    if annotation.extmark_id then
        pcall(vim.api.nvim_buf_del_extmark, bufnr, M.NS, annotation.extmark_id)
        annotation.extmark_id = nil
        annotation.bufnr = nil
    end
end

--- Clear and re-render all signs for the file that corresponds to bufnr.
---@param bufnr number|nil  defaults to current buffer
function M.render_buffer(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    local store = require("meow.review.store")

    local abs = vim.api.nvim_buf_get_name(bufnr)
    if abs == "" then
        return
    end
    local root = store.current_root()
    local rel = abs:gsub("^" .. vim.pesc(root) .. "/", "")
    if rel == abs then
        rel = vim.fn.fnamemodify(abs, ":.")
    end

    -- Clear existing extmarks (signs + trackers) for this buffer
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, M.NS, 0, -1)

    -- Re-place all annotations for this file
    for _, ann in ipairs(store.all()) do
        if ann.file == rel then
            ann.extmark_id = nil -- reset so place() creates a fresh one
            ann.bufnr = nil

            -- Compute stale: annotation has a snippet and it differs from the current line.
            if ann.snippet and ann.snippet ~= "" and not ann.hunk_head then
                local cur = vim.api.nvim_buf_get_lines(bufnr, ann.lnum - 1, ann.lnum, false)
                ann.stale = (cur[1] ~= nil) and (vim.trim(cur[1]) ~= vim.trim(ann.snippet))
            else
                ann.stale = false
            end

            M.place(ann, bufnr)
        end
    end
end

--- Render annotations in all currently loaded buffers that have matching files.
function M.render_all()
    local store = require("meow.review.store")
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            local abs = vim.api.nvim_buf_get_name(bufnr)
            if abs ~= "" then
                local root = store.current_root()
                local rel = abs:gsub("^" .. vim.pesc(root) .. "/", "")
                if rel == abs then
                    rel = vim.fn.fnamemodify(abs, ":.")
                end
                if store.has_file(rel) then
                    M.render_buffer(bufnr)
                end
            end
        end
    end
end

return M
