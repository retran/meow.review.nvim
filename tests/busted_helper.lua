-- tests/busted_helper.lua
-- Busted helper loaded before specs via --helper flag.
-- Configures the Neovim runtimepath so plugin modules are resolvable.

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

-- Ensure the plugin root is on the rtp so require("meow.review.*") works
vim.opt.rtp:prepend(root)

-- nui.nvim: required runtime dependency for ui.lua tests
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
