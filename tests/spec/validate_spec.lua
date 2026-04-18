-- tests/spec/validate_spec.lua
-- Tests for lua/meow/review/validate.lua
-- Run with: make test

local assert = require("luassert")

describe("meow.review.validate", function()
    local validate
    local tmpdir

    before_each(function()
        -- Reset modules
        package.loaded["meow.review.validate"] = nil
        package.loaded["meow.review.signs"] = nil
        package.loaded["meow.review.types"] = nil

        -- Stub signs and types
        package.loaded["meow.review.signs"] = { NS = 0 }
        package.loaded["meow.review.types"] = {
            get = function(_) return { icon = "!" } end,
        }

        validate = require("meow.review.validate")

        -- Create a temp directory with a test file
        tmpdir = vim.fn.tempname()
        vim.fn.mkdir(tmpdir, "p")
    end)

    after_each(function()
        vim.fn.delete(tmpdir, "rf")
    end)

    -- Helper: write a file to tmpdir
    local function write_file(rel, lines)
        local abs = tmpdir .. "/" .. rel
        -- Create parent dir if needed
        local parent = abs:match("^(.*)/[^/]*$")
        if parent then vim.fn.mkdir(parent, "p") end
        local f = io.open(abs, "w")
        f:write(table.concat(lines, "\n") .. "\n")
        f:close()
    end

    describe("check()", function()
        it("marks annotation non-stale when file exists and lnum is in range", function()
            write_file("foo.lua", { "line 1", "line 2", "line 3" })
            local ann = { file = "foo.lua", lnum = 2, type = "NOTE", text = "x", id = "1" }
            local results = validate.check({ ann }, tmpdir)
            assert.equal(1, #results)
            assert.is_false(results[1].stale)
            assert.equal("ok", results[1].reason)
        end)

        it("marks annotation stale when file does not exist", function()
            local ann = { file = "missing.lua", lnum = 1, type = "NOTE", text = "x", id = "2" }
            local results = validate.check({ ann }, tmpdir)
            assert.equal(1, #results)
            assert.is_true(results[1].stale)
            assert.truthy(results[1].reason:find("file not found"))
        end)

        it("marks annotation stale when lnum exceeds file length", function()
            write_file("short.lua", { "only one line" })
            local ann = { file = "short.lua", lnum = 99, type = "NOTE", text = "x", id = "3" }
            local results = validate.check({ ann }, tmpdir)
            assert.is_true(results[1].stale)
            assert.truthy(results[1].reason:find("no longer exists"))
        end)

        it("returns empty results for empty annotations list", function()
            local results = validate.check({}, tmpdir)
            assert.same({}, results)
        end)

        it("marks annotation stale when snippet content no longer matches", function()
            write_file("changed.lua", { "function foo()", "  return 42", "end" })
            -- snippet_start = 1, first snippet line is different from current file line 1
            local ann = {
                file = "changed.lua",
                lnum = 1,
                snippet_start = 1,
                snippet = "1: function bar()\n2:   return 99\n",
                type = "ISSUE",
                text = "wrong",
                id = "4",
            }
            local results = validate.check({ ann }, tmpdir)
            assert.is_true(results[1].stale)
            assert.truthy(results[1].reason:find("content has changed"))
        end)

        it("marks annotation non-stale when snippet matches current file content", function()
            write_file("same.lua", { "function foo()", "  return 42", "end" })
            local ann = {
                file = "same.lua",
                lnum = 1,
                snippet_start = 1,
                snippet = "1: function foo()\n2:   return 42\n",
                type = "NOTE",
                text = "ok",
                id = "5",
            }
            local results = validate.check({ ann }, tmpdir)
            assert.is_false(results[1].stale)
        end)
    end)
end)
