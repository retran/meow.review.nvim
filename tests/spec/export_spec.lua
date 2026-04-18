-- tests/spec/export_spec.lua
-- Tests for lua/meow/review/export.lua (formatter registry)
-- Run with: make test

local assert = require("luassert")

describe("meow.review.export", function()
    local export

    before_each(function()
        package.loaded["meow.review.export"] = nil
        package.loaded["meow.review.config.internal"] = nil
        package.loaded["meow.review.utils"] = {
            resolve_path = function(p, root)
                if p:sub(1, 1) == "/" then return p end
                return root .. "/" .. p
            end,
            ensure_parent_dirs = function() end,
        }
        vim.g.meow_review = nil
        export = require("meow.review.export")
    end)

    after_each(function()
        package.loaded["meow.review.export"] = nil
        package.loaded["meow.review.config.internal"] = nil
        package.loaded["meow.review.utils"] = nil
    end)

    -- ── Formatter registry ────────────────────────────────────────────────────

    describe("register_formatter() / list_formatters()", function()
        it("registers a formatter and returns it in list", function()
            export.register_formatter("test_fmt", function(_) return "test" end)
            local list = export.list_formatters()
            local found = false
            for _, n in ipairs(list) do
                if n == "test_fmt" then found = true end
            end
            assert.is_true(found)
        end)

        it("unregister_formatter removes it from the list", function()
            export.register_formatter("to_remove", function(_) return "" end)
            export.unregister_formatter("to_remove")
            local list = export.list_formatters()
            for _, n in ipairs(list) do
                assert.not_equal("to_remove", n)
            end
        end)

        it("replacing a formatter with the same name keeps order", function()
            export.register_formatter("a", function(_) return "v1" end)
            export.register_formatter("b", function(_) return "b" end)
            export.register_formatter("a", function(_) return "v2" end)
            -- "a" should still be in the list (order preserved, not duplicated)
            local count = 0
            for _, n in ipairs(export.list_formatters()) do
                if n == "a" then count = count + 1 end
            end
            assert.equal(1, count)
        end)
    end)

    -- ── Built-in formatters ───────────────────────────────────────────────────

    describe("built-in formatters (registered via setup_builtins)", function()
        before_each(function()
            export.setup_builtins({ disabled_exporters = {} })
        end)

        it("'markdown' formatter is registered", function()
            local list = export.list_formatters()
            local found = false
            for _, n in ipairs(list) do
                if n == "markdown" then found = true end
            end
            assert.is_true(found)
        end)

        it("'json' formatter is registered", function()
            local list = export.list_formatters()
            local found = false
            for _, n in ipairs(list) do
                if n == "json" then found = true end
            end
            assert.is_true(found)
        end)
    end)

    -- ── build_markdown ────────────────────────────────────────────────────────

    describe("build_markdown()", function()
        it("includes file section heading", function()
            local md = export.build_markdown({
                { file = "foo.lua", lnum = 1, end_lnum = 1, type = "ISSUE", text = "bad", timestamp = os.time() },
            }, "")
            assert.truthy(md:find("## @foo.lua"))
        end)

        it("includes annotation type in heading", function()
            local md = export.build_markdown({
                { file = "bar.lua", lnum = 5, end_lnum = 5, type = "NOTE", text = "note text", timestamp = os.time() },
            }, "")
            assert.truthy(md:find("%[NOTE%]"))
        end)

        it("includes annotation text", function()
            local md = export.build_markdown({
                { file = "baz.lua", lnum = 1, end_lnum = 1, type = "SUGGESTION", text = "refactor this", timestamp = os.time() },
            }, "")
            assert.truthy(md:find("refactor this"))
        end)

        it("includes preamble when provided", function()
            local md = export.build_markdown({
                { file = "x.lua", lnum = 1, end_lnum = 1, type = "NOTE", text = "hi", timestamp = os.time() },
            }, "MY PREAMBLE")
            assert.truthy(md:find("MY PREAMBLE"))
        end)

        it("omits preamble when empty string is passed", function()
            local md = export.build_markdown({
                { file = "x.lua", lnum = 1, end_lnum = 1, type = "NOTE", text = "hi", timestamp = os.time() },
            }, "")
            assert.falsy(md:find("MY PREAMBLE"))
        end)
    end)

    -- ── Summary block ─────────────────────────────────────────────────────────

    describe("build_markdown() summary block", function()
        local anns = {
            { file = "src/foo.lua", lnum = 1, end_lnum = 1, type = "ISSUE",      text = "a", timestamp = os.time() },
            { file = "src/bar.lua", lnum = 2, end_lnum = 2, type = "SUGGESTION", text = "b", timestamp = os.time() },
            { file = "src/foo.lua", lnum = 5, end_lnum = 5, type = "NOTE",        text = "c", timestamp = os.time() },
        }

        it("export_summary=true produces a ## Summary section", function()
            local md = export.build_markdown(anns, "", true)
            assert.truthy(md:find("## Summary"))
        end)

        it("summary line counts match actual annotations", function()
            local md = export.build_markdown(anns, "", true)
            assert.truthy(md:find("Annotations: 3"))
        end)

        it("summary files count matches unique files", function()
            local md = export.build_markdown(anns, "", true)
            assert.truthy(md:find("Files reviewed: 2"))
        end)

        it("summary file list contains each unique file", function()
            local md = export.build_markdown(anns, "", true)
            assert.truthy(md:find("src/foo.lua"))
            assert.truthy(md:find("src/bar.lua"))
        end)

        it("export_summary=false suppresses ## Summary", function()
            local md = export.build_markdown(anns, "", false)
            assert.falsy(md:find("## Summary"))
        end)

        it("empty preamble + export_summary=true still produces ## Summary", function()
            local md = export.build_markdown(anns, "", true)
            assert.truthy(md:find("## Summary"))
        end)
    end)

    -- ── export() file filter ──────────────────────────────────────────────────

    describe("export() with file filter", function()
        local captured_output
        local stub_annotations

        before_each(function()
            captured_output = nil
            stub_annotations = {
                { file = "src/foo.lua", lnum = 1, end_lnum = 1, type = "ISSUE",      text = "foo issue",  timestamp = os.time() },
                { file = "src/bar.lua", lnum = 2, end_lnum = 2, type = "SUGGESTION", text = "bar suggest", timestamp = os.time() },
            }
            package.loaded["meow.review.store"] = {
                sorted = function() return stub_annotations end,
                current_root = function() return "/tmp/test" end,
            }
            export.setup_builtins({ disabled_exporters = {} })
            -- Register a spy exporter
            export.register("spy", function(output, _)
                captured_output = output
            end)
        end)

        after_each(function()
            package.loaded["meow.review.store"] = nil
        end)

        it("filter.file restricts output to that file's annotations", function()
            export.export("spy", "markdown", { file = "src/foo.lua" })
            assert.truthy(captured_output)
            assert.truthy(captured_output:find("src/foo.lua"))
            assert.falsy(captured_output:find("src/bar.lua"))
        end)

        it("filter.file for nonexistent file warns no annotations", function()
            local notified = false
            vim.notify = function(msg, _)
                if msg:find("No annotations") then notified = true end
            end
            local ok = export.export("spy", "markdown", { file = "nonexistent.lua" })
            assert.is_false(ok)
            assert.is_true(notified)
        end)
    end)

    -- ── avante / codecompanion auto-registration ──────────────────────────────

    describe("setup_builtins() avante/codecompanion auto-registration", function()
        it("registers 'avante' exporter when avante.api is available", function()
            local ask_args = {}
            package.loaded["avante.api"] = {
                ask = function(opts) table.insert(ask_args, opts) end,
            }
            export.setup_builtins({ disabled_exporters = {} })
            local list = export.list()
            local found = false
            for _, n in ipairs(list) do
                if n == "avante" then found = true end
            end
            assert.is_true(found)
            package.loaded["avante.api"] = nil
        end)

        it("does NOT register 'avante' exporter when avante.api is absent", function()
            package.loaded["avante.api"] = nil
            export.setup_builtins({ disabled_exporters = {} })
            local list = export.list()
            for _, n in ipairs(list) do
                assert.not_equal("avante", n)
            end
        end)

        it("registers 'codecompanion' exporter when codecompanion is available", function()
            package.loaded["codecompanion"] = {
                chat = function() end,
            }
            export.setup_builtins({ disabled_exporters = {} })
            local list = export.list()
            local found = false
            for _, n in ipairs(list) do
                if n == "codecompanion" then found = true end
            end
            assert.is_true(found)
            package.loaded["codecompanion"] = nil
        end)

        it("does NOT register 'codecompanion' exporter when codecompanion is absent", function()
            package.loaded["codecompanion"] = nil
            export.setup_builtins({ disabled_exporters = {} })
            local list = export.list()
            for _, n in ipairs(list) do
                assert.not_equal("codecompanion", n)
            end
        end)

        it("calling 'avante' exporter invokes avante_api.ask with markdown", function()
            local ask_args = {}
            package.loaded["avante.api"] = {
                ask = function(opts) table.insert(ask_args, opts) end,
            }
            export.setup_builtins({ disabled_exporters = {} })
            -- Manually call the registered avante exporter
            local avante_fn
            for _, n in ipairs(export.list()) do
                if n == "avante" then
                    -- retrieve via a spy: re-register to capture
                    avante_fn = true
                    break
                end
            end
            assert.is_true(avante_fn)
            -- Call export with a stub store
            package.loaded["meow.review.store"] = {
                sorted = function()
                    return {{ file = "f.lua", lnum = 1, end_lnum = 1, type = "ISSUE", text = "hi", timestamp = os.time() }}
                end,
                current_root = function() return "/tmp" end,
            }
            export.export("avante", "markdown")
            assert.equal(1, #ask_args)
            assert.truthy(ask_args[1].question:find("hi"))
            package.loaded["avante.api"] = nil
            package.loaded["meow.review.store"] = nil
        end)
    end)
end)
