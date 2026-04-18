-- tests/spec/store_spec.lua
-- Tests for lua/meow/review/store.lua

local T = require("mini.test")

local child = T.new_child_neovim()

-- Helper: stub out disk I/O and signs so store can be exercised in isolation
local function setup_store_stubs()
    child.lua("package.loaded['meow.review.store'] = nil")
    child.lua("package.loaded['meow.review.config.internal'] = nil")
    child.lua("package.loaded['meow.review.signs'] = nil")
    child.lua("package.loaded['meow.review.signs'] = { NS = 0, place = function() end, unplace = function() end, render_all = function() end }")
    child.lua("require('meow.review.store').save = function() end")
end

local describe = T.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "scripts/minimal_init.lua" })
            setup_store_stubs()
        end,
        post_once = function()
            child.stop()
        end,
    },
})

-- ── get_project_root ──────────────────────────────────────────────────────────

describe["get_project_root returns a non-empty string"] = function()
    local root = child.lua_get("require('meow.review.store').get_project_root()")
    T.expect.no_equality(root, nil)
    T.expect.no_equality(root, "")
end

describe["get_project_root uses fallback for non-git dir"] = function()
    -- /tmp is unlikely to be a git root; we just verify a string is returned
    local root = child.lua_get("require('meow.review.store').get_project_root('/tmp')")
    T.expect.no_equality(root, nil)
    T.expect.no_equality(root, "")
end

-- ── current_root / set_project_root ──────────────────────────────────────────

describe["current_root reflects set_project_root"] = function()
    child.lua("require('meow.review.store').set_project_root('/fake/root')")
    local root = child.lua_get("require('meow.review.store').current_root()")
    T.expect.equality(root, "/fake/root")
end

-- ── CRUD ──────────────────────────────────────────────────────────────────────

describe["add returns annotation with id and timestamp"] = function()
    child.lua("_G._ann = require('meow.review.store').add({ file = 'foo.lua', lnum = 1, type = 'ISSUE', text = 'bad code' })")
    local id = child.lua_get("_G._ann.id")
    T.expect.no_equality(id, nil)
    T.expect.no_equality(id, "")
    local ts = child.lua_get("_G._ann.timestamp")
    T.expect.no_equality(ts, nil)
    T.expect.equality(child.lua_get("_G._ann.file"), "foo.lua")
end

describe["count reflects number of annotations"] = function()
    child.lua("require('meow.review.store').add({ file = 'a.lua', lnum = 1, type = 'NOTE', text = 'x' })")
    child.lua("require('meow.review.store').add({ file = 'b.lua', lnum = 2, type = 'NOTE', text = 'y' })")
    T.expect.equality(child.lua_get("require('meow.review.store').count()"), 2)
end

describe["delete removes annotation by id"] = function()
    child.lua("local ann = require('meow.review.store').add({ file = 'a.lua', lnum = 1, type = 'NOTE', text = 'x' }); _G._id = ann.id")
    child.lua("require('meow.review.store').delete(_G._id)")
    T.expect.equality(child.lua_get("require('meow.review.store').count()"), 0)
end

describe["delete returns false for unknown id"] = function()
    local deleted = child.lua_get("require('meow.review.store').delete('nonexistent_id')")
    T.expect.equality(deleted, false)
end

describe["update changes text and type"] = function()
    child.lua("local ann = require('meow.review.store').add({ file = 'a.lua', lnum = 1, type = 'NOTE', text = 'original' }); _G._id = ann.id")
    child.lua("require('meow.review.store').update(_G._id, { text = 'updated', type = 'ISSUE' })")
    T.expect.equality(child.lua_get("require('meow.review.store').all()[1].text"), "updated")
    T.expect.equality(child.lua_get("require('meow.review.store').all()[1].type"), "ISSUE")
end

describe["clear removes all annotations"] = function()
    child.lua("require('meow.review.store').add({ file = 'a.lua', lnum = 1, type = 'NOTE', text = 'x' })")
    child.lua("require('meow.review.store').add({ file = 'b.lua', lnum = 2, type = 'NOTE', text = 'y' })")
    child.lua("require('meow.review.store').clear()")
    T.expect.equality(child.lua_get("require('meow.review.store').count()"), 0)
end

-- ── Queries ───────────────────────────────────────────────────────────────────

describe["get_at_line returns annotations covering that line"] = function()
    child.lua("require('meow.review.store').add({ file = 'a.lua', lnum = 5, end_lnum = 10, type = 'NOTE', text = 'x' })")
    T.expect.equality(#child.lua_get("require('meow.review.store').get_at_line('a.lua', 7)"), 1)
    T.expect.equality(#child.lua_get("require('meow.review.store').get_at_line('a.lua', 15)"), 0)
end

describe["sorted returns annotations in file+lnum order"] = function()
    child.lua("require('meow.review.store').add({ file = 'b.lua', lnum = 1, type = 'NOTE', text = 'b' })")
    child.lua("require('meow.review.store').add({ file = 'a.lua', lnum = 5, type = 'NOTE', text = 'a' })")
    child.lua("require('meow.review.store').add({ file = 'a.lua', lnum = 2, type = 'NOTE', text = 'c' })")
    local sorted = child.lua_get("require('meow.review.store').sorted()")
    T.expect.equality(sorted[1].file, "a.lua")
    T.expect.equality(sorted[1].lnum, 2)
    T.expect.equality(sorted[2].lnum, 5)
    T.expect.equality(sorted[3].file, "b.lua")
end

describe["find_next wraps around to first annotation"] = function()
    child.lua("require('meow.review.store').add({ file = 'a.lua', lnum = 1, type = 'NOTE', text = 'x' })")
    T.expect.equality(child.lua_get("require('meow.review.store').find_next('z.lua', 999).file"), "a.lua")
end

describe["find_prev wraps around to last annotation"] = function()
    child.lua("require('meow.review.store').add({ file = 'z.lua', lnum = 99, type = 'NOTE', text = 'x' })")
    T.expect.equality(child.lua_get("require('meow.review.store').find_prev('a.lua', 1).file"), "z.lua")
end

describe["has_file returns true iff file has annotations"] = function()
    child.lua("require('meow.review.store').add({ file = 'present.lua', lnum = 1, type = 'NOTE', text = 'x' })")
    T.expect.equality(child.lua_get("require('meow.review.store').has_file('present.lua')"), true)
    T.expect.equality(child.lua_get("require('meow.review.store').has_file('absent.lua')"), false)
end

-- ── ID uniqueness ─────────────────────────────────────────────────────────────

describe["add() generates unique IDs for rapid successive calls"] = function()
    for i = 1, 10 do
        child.lua("require('meow.review.store').add({ file = 'f.lua', lnum = " .. i .. ", type = 'NOTE', text = 'x" .. i .. "' })")
    end
    local all = child.lua_get("require('meow.review.store').all()")
    local seen = {}
    for _, ann in ipairs(all) do
        T.expect.equality(seen[ann.id], nil) -- no duplicate
        seen[ann.id] = true
    end
    T.expect.equality(#all, 10)
end

describe["add() IDs are non-empty strings"] = function()
    child.lua("_G._ann2 = require('meow.review.store').add({ file = 'f.lua', lnum = 1, type = 'NOTE', text = 'y' })")
    local id = child.lua_get("_G._ann2.id")
    T.expect.no_equality(id, nil)
    T.expect.no_equality(id, "")
    T.expect.equality(type(id), "string")
end

return describe
