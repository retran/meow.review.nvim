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
            get_store_path = function()
                return "/tmp/test-root/.cache/meow-review/annotations.json"
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
end)
