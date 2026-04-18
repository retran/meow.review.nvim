-- scripts/run_busted.lua
-- Wrapper: patches package.path so Neovim's LuaJIT can find the luarocks-
-- installed busted/luassert modules, then delegates to the busted runner.
--
-- Usage (via nlua):
--   nlua scripts/run_busted.lua [busted args...]

-- Inject the user luarocks tree for Lua 5.1
local luarocks_tree = vim.fn.expand("~/.luarocks/share/lua/5.1")
package.path = luarocks_tree .. "/?.lua;" .. luarocks_tree .. "/?/init.lua;" .. package.path

local cluarocks_tree = vim.fn.expand("~/.luarocks/lib/lua/5.1")
package.cpath = cluarocks_tree .. "/?.so;" .. package.cpath

-- Inject the plugin root so require("meow.review.*") resolves
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

-- nui.nvim: required runtime dependency
local nui_path = root .. "/deps/nui.nvim"
if vim.fn.isdirectory(nui_path) == 0 then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "--depth=1",
        "https://github.com/MunifTanjim/nui.nvim",
        nui_path,
    })
end
vim.opt.rtp:prepend(nui_path)

-- Forward remaining args as busted args
local busted_args = {}
for i = 1, #arg do
    table.insert(busted_args, arg[i])
end

-- Run busted programmatically
local busted_runner = require("busted.runner")

-- busted.runner expects the CLI args in _G.arg
_G.arg = busted_args

busted_runner({ standalone = false })
