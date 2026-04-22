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
-- @file: plugin/meow-review.lua
-- @brief: Entry point for meow.review.nvim — automatically loaded by Neovim.
-- @author: Andrew Vasilyev
-- @license: MIT

-- Prevent loading the plugin multiple times
if vim.g.loaded_meow_review then
    return
end
vim.g.loaded_meow_review = 1

-- Check Neovim version compatibility
if vim.fn.has("nvim-0.11.0") == 0 then
    vim.api.nvim_err_writeln("meow.review.nvim requires Neovim >= 0.11.0")
    return
end

-- Defer dependency check until the plugin is actually used
local function check_dependencies()
    local has_nui, _ = pcall(require, "nui.input")
    if not has_nui then
        vim.api.nvim_err_writeln("meow.review.nvim requires nui.nvim (https://github.com/MunifTanjim/nui.nvim)")
        return false
    end
    return true
end

---@class MeowReviewSubcommand
---@field impl fun(args: string[], opts: table) The command implementation
---@field complete? fun(subcmd_arg_lead: string): string[] Optional completions callback

---@type table<string, MeowReviewSubcommand>
local subcommand_tbl = {
    add = {
        impl = function(_, opts)
            if not check_dependencies() then
                return
            end
            require("meow.review").add_comment(opts.range > 0)
        end,
    },
    delete = {
        impl = function(_, _)
            if not check_dependencies() then
                return
            end
            require("meow.review").delete_comment()
        end,
    },
    view = {
        impl = function(_, _)
            if not check_dependencies() then
                return
            end
            require("meow.review").view_comment()
        end,
    },
    export = {
        impl = function(args, _)
            if not check_dependencies() then
                return
            end
            -- args[1] is an optional exporter name; nil means use default_exporter (clipboard)
            require("meow.review").export_review(args[1])
        end,
        complete = function(_)
            local ok, exp = pcall(require, "meow.review.export")
            if ok then
                return exp.list()
            end
            return {}
        end,
    },
    clear = {
        impl = function(_, _)
            if not check_dependencies() then
                return
            end
            require("meow.review").clear_all()
        end,
    },
    ["goto"] = {
        impl = function(_, _)
            if not check_dependencies() then
                return
            end
            require("meow.review").goto_comment()
        end,
    },
    goto_file = {
        impl = function(_, _)
            if not check_dependencies() then
                return
            end
            require("meow.review").goto_comment_in_file()
        end,
    },
    goto_type = {
        impl = function(args, _)
            if not check_dependencies() then
                return
            end
            require("meow.review").goto_comment_by_type(args[1])
        end,
    },
    edit = {
        impl = function(_, _)
            if not check_dependencies() then
                return
            end
            require("meow.review").edit_comment()
        end,
    },
    reload = {
        impl = function(_, _)
            if not check_dependencies() then
                return
            end
            require("meow.review").reload()
        end,
    },
    validate = {
        impl = function(_, _)
            require("meow.review").validate()
        end,
    },
    resolve = {
        impl = function(_, _)
            if not check_dependencies() then
                return
            end
            require("meow.review").resolve_comment()
        end,
    },
    resolve_all = {
        impl = function(_, _)
            if not check_dependencies() then
                return
            end
            require("meow.review").resolve_all_comments()
        end,
    },
    export_and_clear = {
        impl = function(args, _)
            if not check_dependencies() then
                return
            end
            require("meow.review").export_and_clear(args[1])
        end,
        complete = function(_)
            local ok, exp = pcall(require, "meow.review.export")
            if ok then
                return exp.list()
            end
            return {}
        end,
    },
    export_file = {
        impl = function(args, _)
            if not check_dependencies() then
                return
            end
            require("meow.review").export_current_file(args[1])
        end,
        complete = function(_)
            local ok, exp = pcall(require, "meow.review.export")
            if ok then
                return exp.list()
            end
            return {}
        end,
    },
    next = {
        impl = function(_, _)
            require("meow.review").next_comment()
        end,
    },
    prev = {
        impl = function(_, _)
            require("meow.review").prev_comment()
        end,
    },
}

---@param opts table :h lua-guide-commands-create
local function meow_review_cmd(opts)
    local fargs = opts.fargs
    local subcommand_key = fargs[1]

    if not subcommand_key or subcommand_key == "" then
        vim.notify(
            "Usage: :MeowReview <add|delete|edit|view|export [name]|clear|goto|reload|validate|next|prev>",
            vim.log.levels.ERROR
        )
        return
    end

    local args = #fargs > 1 and vim.list_slice(fargs, 2, #fargs) or {}
    local subcommand = subcommand_tbl[subcommand_key]

    if not subcommand then
        vim.notify("MeowReview: Unknown command: " .. subcommand_key, vim.log.levels.ERROR)
        return
    end

    subcommand.impl(args, opts)
end

-- Create the main :MeowReview command with tab-completion
vim.api.nvim_create_user_command("MeowReview", meow_review_cmd, {
    nargs = "*",
    range = true,
    desc = "Code review annotation tool"
        .. " (Usage: MeowReview <add|delete|edit|view|export [name]|clear|goto|reload|next|prev>)",
    complete = function(arg_lead, cmdline, _)
        -- First arg: complete subcommand names
        if cmdline:match("^['<,'>]*MeowReview[!]*%s+%w*$") then
            local subcommand_keys = vim.tbl_keys(subcommand_tbl)
            return vim.iter(subcommand_keys)
                :filter(function(key)
                    return key:find(arg_lead) ~= nil
                end)
                :totable()
        end
        -- Second arg for 'export': complete registered exporter names
        local subcmd = cmdline:match("^['<,'>]*MeowReview[!]*%s+(%w+)%s+")
        if subcmd and subcommand_tbl[subcmd] and subcommand_tbl[subcmd].complete then
            return vim.iter(subcommand_tbl[subcmd].complete(arg_lead))
                :filter(function(key)
                    return key:find(arg_lead) ~= nil
                end)
                :totable()
        end
    end,
})

-- <Plug> mappings for keymap configuration without hard-coded keys
vim.keymap.set({ "n", "v" }, "<Plug>(MeowReviewAdd)", function()
    if not check_dependencies() then
        return
    end
    -- In visual mode the mapping fires after mode reverts to normal;
    -- pass is_visual=true so add_comment() reads the '< '> marks.
    local mode = vim.fn.mode()
    local from_visual = mode == "v" or mode == "V" or mode == "\22"
    require("meow.review").add_comment(from_visual)
end, { desc = "Add review comment" })

vim.keymap.set({ "n", "v" }, "<Plug>(MeowReviewDelete)", function()
    if not check_dependencies() then
        return
    end
    require("meow.review").delete_comment()
end, { desc = "Delete review comment" })

vim.keymap.set("n", "<Plug>(MeowReviewView)", function()
    if not check_dependencies() then
        return
    end
    require("meow.review").view_comment()
end, { desc = "View review comment" })

vim.keymap.set("n", "<Plug>(MeowReviewExport)", function()
    if not check_dependencies() then
        return
    end
    require("meow.review").export_review()
end, { desc = "Export review to markdown" })

vim.keymap.set("n", "<Plug>(MeowReviewClear)", function()
    if not check_dependencies() then
        return
    end
    require("meow.review").clear_all()
end, { desc = "Clear all review comments" })

vim.keymap.set("n", "<Plug>(MeowReviewEdit)", function()
    if not check_dependencies() then
        return
    end
    require("meow.review").edit_comment()
end, { desc = "Edit review comment" })

vim.keymap.set("n", "<Plug>(MeowReviewGoto)", function()
    if not check_dependencies() then
        return
    end
    require("meow.review").goto_comment()
end, { desc = "Go to review comment" })

vim.keymap.set("n", "<Plug>(MeowReviewGotoFile)", function()
    if not check_dependencies() then
        return
    end
    require("meow.review").goto_comment_in_file()
end, { desc = "Go to review comment in current file" })

vim.keymap.set("n", "<Plug>(MeowReviewGotoType)", function()
    if not check_dependencies() then
        return
    end
    require("meow.review").goto_comment_by_type()
end, { desc = "Go to review comment filtered by type" })

vim.keymap.set("n", "<Plug>(MeowReviewReload)", function()
    require("meow.review").reload()
end, { desc = "Reload review from .meow-review.json" })

vim.keymap.set("n", "<Plug>(MeowReviewNext)", function()
    require("meow.review").next_comment()
end, { desc = "Go to next review comment" })

vim.keymap.set("n", "<Plug>(MeowReviewPrev)", function()
    require("meow.review").prev_comment()
end, { desc = "Go to previous review comment" })

vim.keymap.set("n", "<Plug>(MeowReviewResolve)", function()
    if not check_dependencies() then
        return
    end
    require("meow.review").resolve_comment()
end, { desc = "Resolve review comment at cursor" })

vim.keymap.set("n", "<Plug>(MeowReviewResolveAll)", function()
    if not check_dependencies() then
        return
    end
    require("meow.review").resolve_all_comments()
end, { desc = "Resolve all review comments" })

vim.keymap.set("n", "<Plug>(MeowReviewExportAndClear)", function()
    if not check_dependencies() then
        return
    end
    require("meow.review").export_and_clear()
end, { desc = "Export review and clear annotations" })

vim.keymap.set("n", "<Plug>(MeowReviewExportFile)", function()
    if not check_dependencies() then
        return
    end
    require("meow.review").export_current_file()
end, { desc = "Export review for current file" })

vim.keymap.set("n", "<Plug>(MeowReviewValidate)", function()
    if not check_dependencies() then
        return
    end
    require("meow.review").validate()
end, { desc = "Validate annotations for staleness" })

-- Sign and highlight initialisation (minimal overhead, no module load)
vim.api.nvim_set_hl(0, "MeowReviewIssue", { link = "DiagnosticError", default = true })
vim.api.nvim_set_hl(0, "MeowReviewSuggestion", { link = "DiagnosticWarn", default = true })
vim.api.nvim_set_hl(0, "MeowReviewNote", { link = "DiagnosticInfo", default = true })
vim.api.nvim_set_hl(0, "MeowReviewStale", { link = "DiagnosticHint", default = true })
vim.api.nvim_set_hl(0, "MeowReviewResolved", { link = "Comment", default = true })
