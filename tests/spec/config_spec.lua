-- tests/spec/config_spec.lua
-- Tests for lua/meow/review/config/internal.lua
-- Run with: make test

local assert = require("luassert")

describe("meow.review.config.internal", function()
    local config

    before_each(function()
        package.loaded["meow.review.config.internal"] = nil
        vim.g.meow_review = nil
        config = require("meow.review.config.internal")
    end)

    describe("get()", function()
        it("returns defaults when no user config is set", function()
            local cfg = config.get()
            assert.equal(3, cfg.context_lines)
            assert.equal("clipboard", cfg.default_exporter)
            assert.equal(".cache/meow-review/review.md", cfg.export_filename)
            assert.equal(".cache/meow-review/annotations.json", cfg.store_path)
            assert.same({}, cfg.disabled_exporters)
            assert.equal(64, cfg.modal_width)
            assert.equal(6, cfg.modal_height)
            assert.equal("<C-t>", cfg.modal_cycle_key)
        end)
        it("merges user config over defaults", function()
            vim.g.meow_review = { context_lines = 5, default_exporter = "file" }
            package.loaded["meow.review.config.internal"] = nil
            local cfg = require("meow.review.config.internal").get()
            assert.equal(5, cfg.context_lines)
            assert.equal("file", cfg.default_exporter)
            -- untouched defaults survive
            assert.equal(".cache/meow-review/review.md", cfg.export_filename)
        end)

        it("supports a callable vim.g.meow_review", function()
            vim.g.meow_review = function()
                return { context_lines = 10 }
            end
            package.loaded["meow.review.config.internal"] = nil
            local cfg = require("meow.review.config.internal").get()
            assert.equal(10, cfg.context_lines)
        end)

        it("falls back to defaults on invalid user config", function()
            vim.g.meow_review = { context_lines = "not_a_number" }
            package.loaded["meow.review.config.internal"] = nil
            local cfg = require("meow.review.config.internal").get()
            -- should fall back to default (3), not crash
            assert.equal(3, cfg.context_lines)
        end)
    end)

    describe("validate()", function()
        it("returns true for a valid config", function()
            local ok, err = config.validate({
                context_lines = 3,
                disabled_exporters = {},
                default_exporter = "clipboard",
                default_formatter = "markdown",
                export_filename = ".md",
                store_path = "path",
                modal_width = 64,
                modal_height = 6,
                modal_cycle_key = "<C-t>",
                prompt_preamble = "text",
                export_summary = true,
            })
            assert.is_true(ok)
            assert.is_nil(err)
        end)

        it("returns false for wrong type on context_lines", function()
            local ok, err = config.validate({
                context_lines = "bad",
                disabled_exporters = {},
                default_exporter = "clipboard",
                default_formatter = "markdown",
                export_filename = ".md",
                store_path = "path",
                modal_width = 64,
                modal_height = 6,
                modal_cycle_key = "<C-t>",
                prompt_preamble = "text",
                export_summary = true,
            })
            assert.is_false(ok)
            assert.is_string(err)
        end)

        it("returns false for wrong type on modal_width", function()
            local ok, err = config.validate({
                context_lines = 3,
                disabled_exporters = {},
                default_exporter = "clipboard",
                default_formatter = "markdown",
                export_filename = ".md",
                store_path = "path",
                modal_width = "wide",
                modal_height = 6,
                modal_cycle_key = "<C-t>",
                prompt_preamble = "text",
                export_summary = true,
            })
            assert.is_false(ok)
            assert.is_string(err)
        end)
    end)
end)
