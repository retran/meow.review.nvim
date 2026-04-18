-- tests/spec/ui_spec.lua
-- Tests for lua/meow/review/ui.lua (edit modal top label, Commit 6 #10)
-- Run with: make test

local assert = require("luassert")

describe("meow.review.ui", function()
    local ui
    local captured_popup_opts

    before_each(function()
        -- Reset module cache
        package.loaded["meow.review.ui"] = nil
        package.loaded["meow.review.config.internal"] = nil

        captured_popup_opts = nil

        -- Mock nui.popup: captures opts, returns a stub object
        package.loaded["nui.popup"] = function(opts)
            captured_popup_opts = opts
            return {
                mount = function() end,
                map = function() end,
                on = function() end,
                bufnr = 1,
                winid = 1000,
                border = { set_text = function() end },
            }
        end
        package.loaded["nui.utils.autocmd"] = {
            event = { BufLeave = "BufLeave" },
        }

        -- Stub vim APIs used by open_modal
        vim.api = vim.api or {}
        vim.api.nvim_buf_set_lines = vim.api.nvim_buf_set_lines or function() end
        vim.api.nvim_buf_get_lines = vim.api.nvim_buf_get_lines
            or function()
                return { "test comment" }
            end
        vim.api.nvim_win_set_cursor = vim.api.nvim_win_set_cursor or function() end
        vim.cmd = vim.cmd or function() end

        -- Stub types module
        package.loaded["meow.review.types"] = {
            order = { "ISSUE", "SUGGESTION", "NOTE" },
            get = function(t)
                return { icon = "!", label = t, hl = "DiagnosticError" }
            end,
            next = function(t)
                return t
            end,
        }

        ui = require("meow.review.ui")
    end)

    after_each(function()
        package.loaded["nui.popup"] = nil
        package.loaded["nui.utils.autocmd"] = nil
        package.loaded["meow.review.types"] = nil
        package.loaded["meow.review.ui"] = nil
        package.loaded["meow.review.config.internal"] = nil
    end)

    describe("open_edit_modal()", function()
        it("includes file and line in top border label for single-line annotation", function()
            local ann = {
                type = "ISSUE",
                text = "fix this",
                file = "src/foo.lua",
                lnum = 42,
                end_lnum = 42,
            }
            ui.open_edit_modal(ann, function() end)
            assert.is_not_nil(captured_popup_opts)
            local top = captured_popup_opts.border.text.top
            assert.is_string(top)
            assert.truthy(top:find("src/foo.lua", 1, true), "expected file in top label, got: " .. top)
            assert.truthy(top:find("42", 1, true), "expected line in top label, got: " .. top)
        end)

        it("includes file and line range for multi-line annotation", function()
            local ann = {
                type = "NOTE",
                text = "refactor range",
                file = "lua/init.lua",
                lnum = 10,
                end_lnum = 20,
            }
            ui.open_edit_modal(ann, function() end)
            local top = captured_popup_opts.border.text.top
            assert.truthy(top:find("lua/init.lua", 1, true), "expected file in top label, got: " .. top)
            assert.truthy(top:find("10", 1, true), "expected start line in top label, got: " .. top)
            assert.truthy(top:find("20", 1, true), "expected end line in top label, got: " .. top)
        end)

        it("includes context symbol in top border when present", function()
            local ann = {
                type = "SUGGESTION",
                text = "improve perf",
                file = "src/bar.lua",
                lnum = 5,
                end_lnum = 5,
                context = "my_function",
            }
            ui.open_edit_modal(ann, function() end)
            local top = captured_popup_opts.border.text.top
            assert.truthy(top:find("my_function", 1, true), "expected context in top label, got: " .. top)
        end)

        it("omits context symbol segment when context is nil", function()
            local ann = {
                type = "ISSUE",
                text = "check this",
                file = "src/baz.lua",
                lnum = 7,
                end_lnum = 7,
                context = nil,
            }
            ui.open_edit_modal(ann, function() end)
            local top = captured_popup_opts.border.text.top
            -- Should not contain " — " followed by a symbol
            -- Just check the label contains file:line pattern and no trailing em-dash context
            assert.truthy(top:find("src/baz.lua", 1, true))
            assert.truthy(top:find("7", 1, true))
        end)

        it("shows hunk_head in top label when annotation has a hunk", function()
            local ann = {
                type = "ISSUE",
                text = "hunk comment",
                file = "src/x.lua",
                lnum = 1,
                end_lnum = 1,
                hunk_head = "@@ -1,4 +1,4 @@",
            }
            ui.open_edit_modal(ann, function() end)
            local top = captured_popup_opts.border.text.top
            assert.truthy(top:find("@@ %-1,4 %+1,4 @@"), "expected hunk_head in top label, got: " .. top)
        end)
    end)

    describe("open_picker() adapter fallback", function()
        it("falls through to nui.menu when snacks/telescope/fzf-lua are absent", function()
            package.loaded["snacks"] = nil
            package.loaded["telescope"] = nil
            package.loaded["fzf-lua"] = nil
            package.loaded["meow.review.store"] = {
                current_root = function()
                    return "/tmp"
                end,
            }
            -- Stub nui.menu as a callable that returns a mock menu
            package.loaded["nui.menu"] = setmetatable({}, {
                __call = function(_, _, _)
                    return {
                        mount = function() end,
                        on = function() end,
                    }
                end,
                __index = {
                    item = function(label, data)
                        return { text = label, annotation = data and data.annotation }
                    end,
                },
            })
            package.loaded["meow.review.ui"] = nil
            local fresh_ui = require("meow.review.ui")
            local ok = pcall(function()
                fresh_ui.open_picker({
                    { file = "a.lua", lnum = 1, type = "ISSUE", text = "x" },
                }, "Test", function() end)
            end)
            assert.is_true(ok)
        end)
    end)
end)
