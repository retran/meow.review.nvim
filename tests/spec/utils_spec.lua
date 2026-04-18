-- tests/spec/utils_spec.lua
-- Tests for lua/meow/review/utils.lua
-- Run with: make test

local assert = require("luassert")

describe("meow.review.utils", function()
    local utils

    before_each(function()
        package.loaded["meow.review.utils"] = nil
        utils = require("meow.review.utils")
    end)

    describe("resolve_path()", function()
        it("returns an absolute path unchanged", function()
            local abs = "/home/user/project/annotations.json"
            assert.equal(abs, utils.resolve_path(abs, "/some/root"))
        end)

        it("joins a relative path to the root", function()
            local result = utils.resolve_path("foo/bar.json", "/tmp/root")
            assert.equal("/tmp/root/foo/bar.json", result)
        end)

        it("handles a simple filename relative path", function()
            local result = utils.resolve_path("review.md", "/project")
            assert.equal("/project/review.md", result)
        end)

        it("handles deeply nested relative path", function()
            local result = utils.resolve_path(".cache/meow-review/annotations.json", "/workspace/myproject")
            assert.equal("/workspace/myproject/.cache/meow-review/annotations.json", result)
        end)
    end)
end)
