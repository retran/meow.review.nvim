-- scripts/minimal_init.lua
-- Minimal Neovim init for running tests headlessly with mini.test.
-- Usage: nvim --headless --noplugin -u scripts/minimal_init.lua -l scripts/run_tests.lua

-- Add the plugin root and the test helper directory to the runtimepath so that
-- `require("meow.review.*")` and `require("mini.test")` both resolve correctly.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

-- mini.nvim: expect it to be available as a sibling directory or installed via
-- a package manager.  CI installs it through the bootstrap below.
local mini_path = root .. "/deps/mini.nvim"

if vim.fn.isdirectory(mini_path) == 0 then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "--depth=1",
        "https://github.com/echasnovski/mini.nvim",
        mini_path,
    })
end

vim.opt.rtp:prepend(mini_path)

-- nui.nvim: required dependency for ui.lua tests
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

-- Silence noisy startup messages in headless mode
vim.opt.shortmess:append("I")
