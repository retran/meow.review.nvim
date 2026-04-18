-- tests/spec/config_spec.lua
-- Tests for lua/meow/review/config/internal.lua

local T = require("mini.test")

local child = T.new_child_neovim()

local describe = T.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "scripts/minimal_init.lua" })
            child.lua("package.loaded['meow.review.config.internal'] = nil")
        end,
        post_once = function()
            child.stop()
        end,
    },
})

describe["get() returns defaults when no user config"] = function()
    local cfg = child.lua_get("require('meow.review.config.internal').get()")
    T.expect.equality(cfg.context_lines, 3)
    T.expect.equality(cfg.default_exporter, "clipboard")
    T.expect.equality(cfg.export_filename, ".meow-review.md")
    T.expect.equality(cfg.store_path, ".cache/meow-review/annotations.json")
    T.expect.equality(cfg.disabled_exporters, {})
end

describe["get() merges user config over defaults"] = function()
    child.lua("vim.g.meow_review = { context_lines = 5, default_exporter = 'file' }")
    child.lua("package.loaded['meow.review.config.internal'] = nil")
    local cfg = child.lua_get("require('meow.review.config.internal').get()")
    T.expect.equality(cfg.context_lines, 5)
    T.expect.equality(cfg.default_exporter, "file")
    T.expect.equality(cfg.export_filename, ".meow-review.md")
end

describe["get() supports callable vim.g.meow_review"] = function()
    child.lua("vim.g.meow_review = function() return { context_lines = 10 } end")
    child.lua("package.loaded['meow.review.config.internal'] = nil")
    local cfg = child.lua_get("require('meow.review.config.internal').get()")
    T.expect.equality(cfg.context_lines, 10)
end

describe["validate() returns false for wrong types"] = function()
    child.lua("_G._cfg = { context_lines = 'bad', disabled_exporters = {}, default_exporter = 'clipboard', export_filename = '.md', store_path = 'p', prompt_preamble = 'x' }")
    child.lua("local ok, err = require('meow.review.config.internal').validate(_G._cfg); _G._valid_ok = ok; _G._valid_err = err")
    local ok = child.lua_get("_G._valid_ok")
    T.expect.equality(ok, false)
    local err = child.lua_get("_G._valid_err")
    T.expect.no_equality(err, nil)
end

describe["validate() returns true for valid config"] = function()
    child.lua("_G._cfg = { context_lines = 3, disabled_exporters = {}, default_exporter = 'clipboard', export_filename = '.md', store_path = 'p', prompt_preamble = 'x' }")
    child.lua("local ok, err = require('meow.review.config.internal').validate(_G._cfg); _G._valid_ok = ok; _G._valid_err = err")
    local ok = child.lua_get("_G._valid_ok")
    T.expect.equality(ok, true)
    -- err may come back as vim.NIL over the RPC boundary; treat both as "no error"
    local err = child.lua_get("_G._valid_err")
    T.expect.equality(err == nil or err == vim.NIL, true)
end

return describe
