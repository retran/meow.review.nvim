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
end)
