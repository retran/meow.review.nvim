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
-- @file: lua/meow/review/config/internal.lua
-- @brief: Internal configuration management for meow.review.nvim
-- @author: Andrew Vasilyev
-- @license: MIT

---@mod meow.review.config.internal
local M = {}

---@class meow.review.InternalConfig
local default_config = {
    ---@type number
    context_lines = 3,
    ---@type string[]
    disabled_exporters = {},
    ---@type string
    default_exporter = "clipboard",
    ---@type string
    default_formatter = "markdown",
    ---@type string
    export_filename = ".cache/meow-review/review.md",
    ---@type string
    store_path = ".cache/meow-review/annotations.json",
    ---@type number
    modal_width = 64,
    ---@type number
    modal_height = 6,
    ---@type string
    modal_cycle_key = "<C-t>",
    ---@type string|boolean
    auto_gitignore = "prompt",
    ---@type string
    prompt_preamble = "The following annotations were left during a code review. "
        .. "For each annotation, read the code snippet and comment carefully, then apply the requested fix directly to the file. "
        .. "Prefer minimal, targeted edits. Do not refactor unrelated code.",
    ---@type boolean
    export_summary = true,
}

---@param cfg meow.review.InternalConfig
---@return boolean is_valid
---@return string|nil error_message
function M.validate(cfg)
    local ok, err = pcall(vim.validate, {
        context_lines = { cfg.context_lines, "number" },
        disabled_exporters = { cfg.disabled_exporters, "table" },
        default_exporter = { cfg.default_exporter, "string" },
        default_formatter = { cfg.default_formatter, "string" },
        export_filename = { cfg.export_filename, "string" },
        store_path = { cfg.store_path, "string" },
        modal_width = { cfg.modal_width, "number" },
        modal_height = { cfg.modal_height, "number" },
        modal_cycle_key = { cfg.modal_cycle_key, "string" },
        prompt_preamble = { cfg.prompt_preamble, "string" },
        export_summary = { cfg.export_summary, "boolean" },
    })
    if not ok then
        -- Prefix with the config table path so users know exactly what is wrong
        return false, "vim.g.meow_review." .. (err or "unknown error")
    end

    -- Validate auto_gitignore separately (accepts string or boolean)
    local ag = cfg.auto_gitignore
    if ag ~= nil and type(ag) ~= "string" and type(ag) ~= "boolean" then
        return false, "vim.g.meow_review.auto_gitignore: expected string or boolean, got " .. type(ag)
    end

    return true, nil
end

--- Return the merged and validated configuration.
--- Falls back to defaults on validation failure.
---@return meow.review.InternalConfig
function M.get()
    local user_config = type(vim.g.meow_review) == "function" and vim.g.meow_review() or vim.g.meow_review or {}
    ---@type meow.review.InternalConfig
    local cfg = vim.tbl_deep_extend("force", default_config, user_config)

    local is_valid, error_message = M.validate(cfg)
    if not is_valid then
        vim.notify("MeowReview configuration error: " .. (error_message or "Unknown error"), vim.log.levels.ERROR)
        return default_config
    end

    return cfg
end

return M
