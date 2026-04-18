-- scripts/run_tests.lua
-- Run all *_spec.lua files in tests/spec/ via mini.test.
-- Invoked headlessly:
--   nvim --headless --noplugin -u scripts/minimal_init.lua -l scripts/run_tests.lua

local ok, mini_test = pcall(require, "mini.test")
if not ok then
    vim.api.nvim_err_writeln("mini.test not available: " .. tostring(mini_test))
    vim.cmd("cq 1")
    return
end

-- Collect all spec files
local spec_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/tests/spec"
local spec_files = vim.fn.glob(spec_dir .. "/**/*_spec.lua", false, true)

if #spec_files == 0 then
    vim.api.nvim_err_writeln("No spec files found in " .. spec_dir)
    vim.cmd("cq 1")
    return
end

-- Run all specs
local all_pass = true
for _, f in ipairs(spec_files) do
    local ok2, result = pcall(mini_test.run_file, f)
    if not ok2 then
        vim.api.nvim_err_writeln("Error running " .. f .. ": " .. tostring(result))
        all_pass = false
    end
end

if all_pass then
    vim.cmd("qa!")
else
    vim.cmd("cq 1")
end
