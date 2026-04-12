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
-- @brief: Sign column placement and extmark-based position drift tracking.
-- @author: Andrew Vasilyev
-- @license: MIT

---@mod meow.review.signs
local M = {}

--- Extmark namespace for position drift tracking. Used by store.lua too.
M.NS = vim.api.nvim_create_namespace("meow_review")

local SIGN_GROUP = "meow_review"

--- Register sign definitions. Called once from init.lua setup().
--- Also ensures highlight links are established for newly defined types.
function M.setup_signs()
    require("meow.review.types").setup_highlights()
end

--- Place a sign and a tracking extmark for one annotation in bufnr.
--- Populates annotation.extmark_id, annotation.sign_id, and annotation.bufnr (runtime fields).
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

    -- Sign column icon (below diagnostics priority = 10, above default = 0)
    local sign_id = vim.fn.sign_place(0, SIGN_GROUP, t.sign_name, bufnr, {
        lnum = annotation.lnum,
        priority = 5,
    })
    if sign_id and sign_id > 0 then
        annotation.sign_id = sign_id
    end

    -- Extmark for position drift tracking (no visible glyph)
    local ok, extmark_id = pcall(
        vim.api.nvim_buf_set_extmark,
        bufnr,
        M.NS,
        annotation.lnum - 1, -- 0-based
        0,
        { id = annotation.extmark_id or nil } -- reuse id when re-placing
    )

    if ok then
        annotation.extmark_id = extmark_id
        annotation.bufnr = bufnr
    end
end

--- Remove sign and extmark for one annotation from bufnr.
---@param annotation meow.review.Annotation
---@param bufnr number
function M.unplace(annotation, bufnr)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    if annotation.sign_id and annotation.sign_id > 0 then
        pcall(vim.fn.sign_unplace, SIGN_GROUP, { buffer = bufnr, id = annotation.sign_id })
        annotation.sign_id = nil
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

    -- Clear existing signs and extmarks for this buffer
    vim.fn.sign_unplace(SIGN_GROUP, { buffer = bufnr })
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, M.NS, 0, -1)

    -- Re-place all annotations for this file
    for _, ann in ipairs(store.all()) do
        if ann.file == rel then
            ann.extmark_id = nil -- reset so place() creates a fresh one
            ann.bufnr = nil
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
