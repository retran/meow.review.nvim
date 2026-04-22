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

    describe("ensure_parent_dirs()", function()
        local tmp_root

        before_each(function()
            tmp_root = vim.fn.tempname()
        end)

        after_each(function()
            vim.fn.delete(tmp_root, "rf")
        end)

        it("creates missing parent directories", function()
            local path = tmp_root .. "/a/b/c/file.json"
            utils.ensure_parent_dirs(path)
            assert.equal(1, vim.fn.isdirectory(tmp_root .. "/a/b/c"))
        end)

        it("does not error when parent directory already exists", function()
            vim.fn.mkdir(tmp_root, "p")
            local path = tmp_root .. "/file.json"
            assert.has_no.errors(function()
                utils.ensure_parent_dirs(path)
            end)
        end)

        it("creates deeply nested directories in one call", function()
            local path = tmp_root .. "/x/y/z/w/annotations.json"
            utils.ensure_parent_dirs(path)
            assert.equal(1, vim.fn.isdirectory(tmp_root .. "/x/y/z/w"))
        end)
    end)
end)
