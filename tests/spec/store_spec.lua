-- tests/spec/store_spec.lua
-- Tests for lua/meow/review/store.lua
-- Run with: make test

local assert = require("luassert")

-- Stub out disk I/O and the signs module for isolation
local function reset_store()
    package.loaded["meow.review.store"] = nil
    package.loaded["meow.review.config.internal"] = nil
    package.loaded["meow.review.signs"] = nil
    -- Provide a no-op signs stub
    package.loaded["meow.review.signs"] = {
        NS = 0,
        place = function() end,
        unplace = function() end,
        render_all = function() end,
    }
    local s = require("meow.review.store")
    -- Disable disk I/O
    s.save = function() end
    vim.g.meow_review = nil
    return s
end

describe("meow.review.store", function()
    local store

    before_each(function()
        store = reset_store()
    end)

    -- ── get_project_root ──────────────────────────────────────────────────────

    describe("get_project_root()", function()
        it("returns a non-empty string", function()
            local root = store.get_project_root()
            assert.is_string(root)
            assert.truthy(#root > 0)
        end)

        it("returns a non-empty string for a non-git directory", function()
            local root = store.get_project_root("/tmp")
            assert.is_string(root)
            assert.truthy(#root > 0)
        end)
    end)

    -- ── current_root / set_project_root ──────────────────────────────────────

    describe("set_project_root() / current_root()", function()
        it("current_root() reflects set_project_root()", function()
            store.set_project_root("/fake/root")
            assert.equal("/fake/root", store.current_root())
        end)
    end)

    -- ── get_store_path ────────────────────────────────────────────────────────

    describe("get_store_path()", function()
        it("returns a non-empty string", function()
            local p = store.get_store_path("/some/root")
            assert.is_string(p)
            assert.truthy(#p > 0)
        end)

        it("resolves relative store_path against provided root", function()
            local p = store.get_store_path("/my/project")
            assert.equal("/my/project/.cache/meow-review/annotations.json", p)
        end)

        it("passes an absolute store_path through unchanged", function()
            vim.g.meow_review = { store_path = "/absolute/path/store.json" }
            package.loaded["meow.review.config.internal"] = nil
            local p = store.get_store_path("/ignored/root")
            assert.equal("/absolute/path/store.json", p)
        end)
    end)

    -- ── CRUD ──────────────────────────────────────────────────────────────────

    describe("add()", function()
        it("returns the annotation with id and timestamp set", function()
            local ann = store.add({ file = "foo.lua", lnum = 1, type = "ISSUE", text = "bad" })
            assert.is_string(ann.id)
            assert.truthy(#ann.id > 0)
            assert.is_number(ann.timestamp)
            assert.truthy(ann.timestamp > 0)
            assert.equal("foo.lua", ann.file)
        end)

        it("generates unique IDs for rapid successive calls", function()
            local seen = {}
            for i = 1, 20 do
                local ann = store.add({ file = "f.lua", lnum = i, type = "NOTE", text = "x" })
                assert.is_nil(seen[ann.id], "duplicate id: " .. ann.id)
                seen[ann.id] = true
            end
        end)
    end)

    describe("count()", function()
        it("reflects number of annotations", function()
            store.add({ file = "a.lua", lnum = 1, type = "NOTE", text = "x" })
            store.add({ file = "b.lua", lnum = 2, type = "NOTE", text = "y" })
            assert.equal(2, store.count())
        end)

        it("returns 0 when store is empty", function()
            assert.equal(0, store.count())
        end)
    end)

    describe("delete()", function()
        it("removes annotation by id and returns true", function()
            local ann = store.add({ file = "a.lua", lnum = 1, type = "NOTE", text = "x" })
            local deleted = store.delete(ann.id)
            assert.is_true(deleted)
            assert.equal(0, store.count())
        end)

        it("returns false for an unknown id", function()
            assert.is_false(store.delete("nonexistent_id"))
        end)
    end)

    describe("update()", function()
        it("changes text and type of an annotation", function()
            local ann = store.add({ file = "a.lua", lnum = 1, type = "NOTE", text = "original" })
            store.update(ann.id, { text = "updated", type = "ISSUE" })
            local all = store.all()
            assert.equal("updated", all[1].text)
            assert.equal("ISSUE", all[1].type)
        end)

        it("returns false for an unknown id", function()
            assert.is_false(store.update("no_such_id", { text = "x" }))
        end)
    end)

    describe("clear()", function()
        it("removes all annotations", function()
            store.add({ file = "a.lua", lnum = 1, type = "NOTE", text = "x" })
            store.add({ file = "b.lua", lnum = 2, type = "NOTE", text = "y" })
            store.clear()
            assert.equal(0, store.count())
        end)
    end)

    -- ── Queries ───────────────────────────────────────────────────────────────

    describe("get_at_line()", function()
        it("returns annotations covering the given line", function()
            store.add({ file = "a.lua", lnum = 5, end_lnum = 10, type = "NOTE", text = "x" })
            assert.equal(1, #store.get_at_line("a.lua", 7))
            assert.equal(0, #store.get_at_line("a.lua", 15))
        end)

        it("returns empty table for an unknown file", function()
            assert.same({}, store.get_at_line("missing.lua", 1))
        end)
    end)

    describe("sorted()", function()
        it("returns annotations in file+lnum order", function()
            store.add({ file = "b.lua", lnum = 1, type = "NOTE", text = "b" })
            store.add({ file = "a.lua", lnum = 5, type = "NOTE", text = "a" })
            store.add({ file = "a.lua", lnum = 2, type = "NOTE", text = "c" })
            local s = store.sorted()
            assert.equal("a.lua", s[1].file)
            assert.equal(2, s[1].lnum)
            assert.equal(5, s[2].lnum)
            assert.equal("b.lua", s[3].file)
        end)
    end)

    describe("find_next()", function()
        it("wraps around to the first annotation when past the last", function()
            store.add({ file = "a.lua", lnum = 1, type = "NOTE", text = "x" })
            local ann = store.find_next("z.lua", 999)
            assert.equal("a.lua", ann.file)
        end)

        it("returns nil when store is empty", function()
            assert.is_nil(store.find_next("a.lua", 1))
        end)
    end)

    describe("find_prev()", function()
        it("wraps around to the last annotation when before the first", function()
            store.add({ file = "z.lua", lnum = 99, type = "NOTE", text = "x" })
            local ann = store.find_prev("a.lua", 1)
            assert.equal("z.lua", ann.file)
        end)

        it("returns nil when store is empty", function()
            assert.is_nil(store.find_prev("a.lua", 1))
        end)
    end)

    describe("has_file()", function()
        it("returns true iff a file has annotations", function()
            store.add({ file = "present.lua", lnum = 1, type = "NOTE", text = "x" })
            assert.is_true(store.has_file("present.lua"))
            assert.is_false(store.has_file("absent.lua"))
        end)
    end)
end)
