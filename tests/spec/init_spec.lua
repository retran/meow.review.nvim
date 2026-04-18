-- tests/spec/init_spec.lua
-- Tests for lua/meow/review/init.lua (selected public API functions)
-- Run with: make test

local assert = require("luassert")

describe("meow.review.init", function()
    local m

    -- Stub helpers injected before each test
    local stub_store
    local stub_signs
    local ui_select_calls

    before_each(function()
        package.loaded["meow.review.init"] = nil
        package.loaded["meow.review.store"] = nil
        package.loaded["meow.review.signs"] = nil
        package.loaded["meow.review.ui"] = nil
        package.loaded["meow.review.export"] = nil
        package.loaded["meow.review.types"] = nil
        package.loaded["meow.review.config.internal"] = nil
        package.loaded["meow.review.context"] = nil

        ui_select_calls = {}

        stub_store = {
            _annotations = {},
            count = function()
                local n = 0
                for _ in pairs(stub_store._annotations) do n = n + 1 end
                return n
            end,
            clear = function()
                stub_store._annotations = {}
            end,
            sorted = function()
                local t = {}
                for _, v in pairs(stub_store._annotations) do
                    table.insert(t, v)
                end
                return t
            end,
            add = function(ann)
                local id = tostring(os.time()) .. "_" .. math.random(1000)
                ann.id = ann.id or id
                ann.timestamp = ann.timestamp or os.time()
                stub_store._annotations[ann.id] = ann
                return ann
            end,
            load = function() end,
            save = function() end,
            set_project_root = function() end,
            current_root = function()
                return "/tmp/test-root"
            end,
            current_file = function()
                return "current.lua"
            end,
            get_store_path = function()
                return "/tmp/test-root/.cache/meow-review/annotations.json"
            end,
            get_project_root = function()
                return "/tmp/test-root"
            end,
        }

        stub_signs = {
            render_all = function() end,
            render_buffer = function() end,
            setup_signs = function() end,
            place = function() end,
            remove = function() end,
        }

        package.loaded["meow.review.store"] = stub_store
        package.loaded["meow.review.signs"] = stub_signs
        package.loaded["meow.review.types"] = {
            order = { "ISSUE" },
            get = function()
                return { icon = "!", label = "ISSUE", hl = "DiagnosticError" }
            end,
            next = function(t)
                return t
            end,
            setup = function() end,
        }
        package.loaded["meow.review.export"] = {
            setup_builtins = function() end,
            export = function() end,
        }
        package.loaded["meow.review.ui"] = {
            open_picker = function() end,
            open_add_modal = function() end,
            open_edit_modal = function() end,
            open_view_popup = function() end,
        }
        package.loaded["meow.review.context"] = {
            get_symbol = function()
                return nil
            end,
            find_hunk_at_cursor = function()
                return nil
            end,
        }

        -- Stub vim.ui.select to record calls
        vim.ui = vim.ui or {}
        vim.ui.select = function(items, opts, callback)
            table.insert(ui_select_calls, { items = items, opts = opts, callback = callback })
        end

        m = require("meow.review.init")
    end)

    after_each(function()
        package.loaded["meow.review.init"] = nil
        package.loaded["meow.review.store"] = nil
        package.loaded["meow.review.signs"] = nil
    end)

    describe("clear_all()", function()
        it("notifies and returns immediately when no annotations", function()
            local notified = false
            local orig = vim.notify
            vim.notify = function(msg, _)
                if msg:find("No annotations") then notified = true end
            end
            m.clear_all()
            vim.notify = orig
            assert.is_true(notified)
            assert.equal(0, #ui_select_calls)
        end)

        it("calls vim.ui.select when annotations exist", function()
            stub_store.add({ file = "a.lua", lnum = 1, end_lnum = 1, type = "ISSUE", text = "x" })
            m.clear_all()
            assert.equal(1, #ui_select_calls)
        end)

        it("clears annotations when 'Yes, clear all' is chosen", function()
            stub_store.add({ file = "a.lua", lnum = 1, end_lnum = 1, type = "ISSUE", text = "x" })
            m.clear_all()
            -- Simulate the user choosing the first option
            local call = ui_select_calls[1]
            call.callback(call.items[1])
            assert.equal(0, stub_store.count())
        end)

        it("does not clear annotations when Cancel is chosen", function()
            stub_store.add({ file = "a.lua", lnum = 1, end_lnum = 1, type = "ISSUE", text = "x" })
            m.clear_all()
            local call = ui_select_calls[1]
            call.callback("Cancel")
            assert.equal(1, stub_store.count())
        end)

        it("does not clear annotations when callback receives nil (dismissed)", function()
            stub_store.add({ file = "a.lua", lnum = 1, end_lnum = 1, type = "ISSUE", text = "x" })
            m.clear_all()
            local call = ui_select_calls[1]
            call.callback(nil)
            assert.equal(1, stub_store.count())
        end)
    end)

    describe("status()", function()
        it("returns empty string when no annotations", function()
            assert.equal("", m.status())
        end)

        it("returns count string for a single annotation", function()
            stub_store.add({ file = "a.lua", lnum = 1, end_lnum = 1, type = "ISSUE", text = "x" })
            local s = m.status()
            assert.truthy(s:find("1"), "expected '1' in status, got: " .. s)
            assert.truthy(s:find("\u{f07c}") or s:find(" "), "expected icon prefix in status")
        end)

        it("returns total count with type breakdown for mixed types", function()
            stub_store.add({ file = "a.lua", lnum = 1, end_lnum = 1, type = "ISSUE", text = "x" })
            stub_store.add({ file = "a.lua", lnum = 2, end_lnum = 2, type = "ISSUE", text = "y" })
            stub_store.add({ file = "b.lua", lnum = 5, end_lnum = 5, type = "NOTE", text = "z" })
            local s = m.status()
            assert.truthy(s:find("3"), "expected total 3 in status, got: " .. s)
            assert.truthy(s:find("ISSUE"), "expected ISSUE in breakdown, got: " .. s)
            assert.truthy(s:find("NOTE"), "expected NOTE in breakdown, got: " .. s)
        end)

        it("omits breakdown when all annotations share the same type", function()
            stub_store.add({ file = "a.lua", lnum = 1, end_lnum = 1, type = "ISSUE", text = "x" })
            stub_store.add({ file = "a.lua", lnum = 2, end_lnum = 2, type = "ISSUE", text = "y" })
            local s = m.status()
            assert.truthy(s:find("2"), "expected 2 in status, got: " .. s)
            assert.falsy(s:find("%("), "expected no breakdown when single type, got: " .. s)
        end)
    end)

    describe("BufEnter autocmd (debounce)", function()
        it("registers a MeowReviewBufEnter augroup after setup is called", function()
            -- setup() is called lazily on first API use; we trigger it by calling any API
            -- Actually init.lua registers autocmds during setup(). Verify the augroup exists.
            -- We call setup() directly here.
            stub_store._annotations = {}
            m.setup()
            local groups = vim.api.nvim_get_autocmds({ group = "MeowReviewBufEnter" })
            assert.truthy(#groups > 0, "expected MeowReviewBufEnter autocmd to be registered")
        end)
    end)

    describe("goto_comment_in_file()", function()
        it("notifies when no annotations exist in current file", function()
            local notified = false
            local orig = vim.notify
            vim.notify = function(msg, _)
                if msg:find("No annotations") then notified = true end
            end
            -- current_file returns "current.lua" but store is empty
            m.goto_comment_in_file()
            vim.notify = orig
            assert.is_true(notified)
        end)

        it("opens picker with only annotations for current file", function()
            local picker_items
            package.loaded["meow.review.ui"].open_picker = function(items, _, _)
                picker_items = items
            end
            stub_store.add({ file = "current.lua", lnum = 1, end_lnum = 1, type = "NOTE", text = "a" })
            stub_store.add({ file = "other.lua", lnum = 2, end_lnum = 2, type = "ISSUE", text = "b" })
            m.goto_comment_in_file()
            assert.equal(1, #picker_items)
            assert.equal("current.lua", picker_items[1].file)
        end)
    end)

    describe("goto_comment_by_type()", function()
        it("notifies when no annotations exist", function()
            local notified = false
            local orig = vim.notify
            vim.notify = function(msg, _)
                if msg:find("No annotations") then notified = true end
            end
            m.goto_comment_by_type("ISSUE")
            vim.notify = orig
            assert.is_true(notified)
        end)

        it("opens picker filtered by given type when annotations of that type exist", function()
            local picker_items
            package.loaded["meow.review.ui"].open_picker = function(items, _, _)
                picker_items = items
            end
            stub_store.add({ file = "a.lua", lnum = 1, end_lnum = 1, type = "ISSUE", text = "x" })
            stub_store.add({ file = "a.lua", lnum = 2, end_lnum = 2, type = "NOTE", text = "y" })
            m.goto_comment_by_type("ISSUE")
            assert.equal(1, #picker_items)
            assert.equal("ISSUE", picker_items[1].type)
        end)

        it("shows type-selection prompt when type_name is nil", function()
            stub_store.add({ file = "a.lua", lnum = 1, end_lnum = 1, type = "ISSUE", text = "x" })
            m.goto_comment_by_type()
            assert.equal(1, #ui_select_calls)
        end)
    end)
end)
