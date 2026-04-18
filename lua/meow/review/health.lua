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
-- @file: lua/meow/review/health.lua
-- @brief: Health checks for the meow.review plugin.
-- @author: Andrew Vasilyev
-- @license: MIT

---@mod meow.review.health
local M = {}

---@private
local function check_neovim_version()
    vim.health.start("Neovim version")

    local has_080 = vim.fn.has("nvim-0.8.0") == 1
    local has_090 = vim.fn.has("nvim-0.9.0") == 1
    local has_0100 = vim.fn.has("nvim-0.10.0") == 1

    if not has_080 then
        vim.health.error("Neovim >= 0.8.0 is required")
        return false
    end

    local version_str = has_090 and tostring(vim.version()) or "0.8.x"

    if has_0100 then
        vim.health.ok("Neovim " .. version_str .. " (>= 0.10.0, full feature support)")
    elseif has_090 then
        vim.health.ok("Neovim " .. version_str .. " (>= 0.9.0)")
        vim.health.warn("Neovim 0.10+ is recommended for the best experience")
    else
        vim.health.warn(
            "Neovim "
                .. version_str
                .. " (0.8.x) — plugin is functional,"
                .. " but some APIs (e.g. vim.iter) require 0.10+"
        )
    end

    return true
end

---@private
local function check_dependencies()
    vim.health.start("Dependencies")
    local all_ok = true

    local has_nui_input, _ = pcall(require, "nui.input")
    if has_nui_input then
        vim.health.ok("nui.nvim is installed (nui.input available)")
    else
        vim.health.error("nui.nvim is not installed or not accessible. Please install MunifTanjim/nui.nvim")
        all_ok = false
    end

    local has_nui_popup, _ = pcall(require, "nui.popup")
    if has_nui_popup then
        vim.health.ok("nui.popup is available")
    else
        vim.health.error("nui.popup is not available. Please ensure nui.nvim is properly installed")
        all_ok = false
    end

    local has_nui_menu, _ = pcall(require, "nui.menu")
    if has_nui_menu then
        vim.health.ok("nui.menu is available (used as picker fallback)")
    else
        vim.health.warn("nui.menu is not available — summary picker will fall back to Snacks only")
    end

    -- Optional integrations
    local has_ts = pcall(require, "nvim-treesitter")
    if has_ts then
        vim.health.ok("nvim-treesitter is installed (symbol context detection enabled)")
    else
        vim.health.info("nvim-treesitter not found — symbol context detection disabled (optional)")
    end

    local has_gs = pcall(require, "gitsigns")
    if has_gs then
        vim.health.ok("gitsigns.nvim is installed (git hunk detection enabled)")
    else
        vim.health.info("gitsigns.nvim not found — git hunk detection falls back to vim.diff (optional)")
    end

    local has_snacks = pcall(require, "snacks")
    if has_snacks then
        vim.health.ok("snacks.nvim is installed (rich picker with file preview enabled)")
    else
        vim.health.info("snacks.nvim not found — picker falls back to nui.menu (optional)")
    end

    return all_ok
end

---@private
local function check_configuration()
    vim.health.start("Configuration")

    local cfg_ok, config_internal = pcall(require, "meow.review.config.internal")
    if not cfg_ok then
        vim.health.error("Could not load configuration module: " .. tostring(config_internal))
        return false
    end

    local cfg = config_internal.get()
    local is_valid, err = config_internal.validate(cfg)

    if is_valid then
        vim.health.ok("Configuration is valid")
        vim.health.info("context_lines: " .. tostring(cfg.context_lines))
        local disabled = cfg.disabled_exporters or {}
        if #disabled > 0 then
            vim.health.info("disabled_exporters: " .. table.concat(disabled, ", "))
        else
            vim.health.info("disabled_exporters: (none)")
        end
        local preamble = cfg.prompt_preamble or ""
        if preamble == "" then
            vim.health.info("prompt_preamble: (empty — omitted from export)")
        else
            vim.health.info("prompt_preamble: " .. preamble:sub(1, 60) .. (#preamble > 60 and "…" or ""))
        end
    else
        vim.health.error("Configuration validation failed: " .. (err or "unknown error"))
        return false
    end

    if vim.g.meow_review then
        vim.health.info("User configuration detected in vim.g.meow_review")
    else
        vim.health.info("Using default configuration (vim.g.meow_review not set)")
    end

    return true
end

---@private
local function check_exporters()
    vim.health.start("Exporters")

    local exp_ok, exp = pcall(require, "meow.review.export")
    if not exp_ok then
        vim.health.error("Could not load export module: " .. tostring(exp))
        return false
    end

    local registered = exp.list()
    if #registered == 0 then
        vim.health.warn("No exporters registered — call setup() first, or register one via register_exporter()")
    else
        for _, name in ipairs(registered) do
            vim.health.ok("Exporter registered: " .. name)
        end
    end

    local cfg_ok, config_internal = pcall(require, "meow.review.config.internal")
    if cfg_ok then
        local cfg = config_internal.get()
        local disabled = cfg.disabled_exporters or {}
        if #disabled > 0 then
            vim.health.info("Disabled built-in exporters: " .. table.concat(disabled, ", "))
        end
    end

    return true
end

---@private
local function check_store()
    vim.health.start("Store")

    local store_ok, store = pcall(require, "meow.review.store")
    if not store_ok then
        vim.health.error("Could not load store module: " .. tostring(store))
        return false
    end

    local root = store.get_project_root()
    vim.health.info("Detected project root: " .. tostring(root))

    local count = store.count()
    if count > 0 then
        vim.health.ok(string.format("%d annotation(s) loaded", count))
    else
        vim.health.info("No annotations loaded (run :MeowReview add to create one)")
    end

    local abs_store_path = store.get_store_path(root)

    if vim.fn.filereadable(abs_store_path) == 1 then
        vim.health.ok("Annotation store found: " .. abs_store_path)
    else
        vim.health.info("Annotation store not found (will be created on first annotation): " .. abs_store_path)
    end

    return true
end

---@private
local function provide_troubleshooting_info()
    vim.health.start("Troubleshooting Information")

    vim.health.info("Plugin directory: lua/meow/review/")
    vim.health.info("Configuration location: vim.g.meow_review")
    vim.health.info("Health check: :checkhealth meow.review")
    vim.health.info("Annotation store: configurable via store_path (default: .cache/meow-review/annotations.json)")
    vim.health.info("Export output: .review.md (project root) + system clipboard")

    vim.health.info([[
Minimal configuration example:
require("meow.review").setup({ context_lines = 5 })

-- Or via vim.g before setup():
vim.g.meow_review = { context_lines = 5 }]])

    vim.health.info([[
Common issues:
1. Signs not appearing  — Run :MeowReview reload to re-render from the annotation store
2. Wrong project root   — Ensure the file is inside a git repo, or cwd is set correctly
3. nui.nvim errors      — Run :checkhealth to verify nui.nvim is installed
4. Export not working   — Check :messages for write errors on the project root path
]])
end

--- Main health check function called by :checkhealth meow.review
function M.check()
    local nvim_ok = check_neovim_version()
    if not nvim_ok then
        return
    end

    local deps_ok = check_dependencies()
    local cfg_ok = check_configuration()
    check_exporters()
    check_store()
    provide_troubleshooting_info()

    vim.health.start("Summary")
    if deps_ok and cfg_ok then
        vim.health.ok("Plugin is ready to use!")
    else
        vim.health.error("Plugin has configuration or dependency issues — see above for details")
    end
end

return M
