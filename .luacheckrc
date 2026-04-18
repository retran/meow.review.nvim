-- .luacheckrc
-- luacheck configuration for meow.review.nvim

-- Neovim global
globals = { "vim" }

-- Ignore unused self in method definitions
self = false

-- Allow unused arguments prefixed with _
unused_args = true

-- Max line length matches stylua config
max_line_length = 120

-- Ignore common Neovim patterns
ignore = {
    "212", -- Unused argument
    "213", -- Unused loop variable (for _ patterns)
}

-- Per-file overrides
files = {
    ["tests/**/*.lua"] = {
        -- Allow test helpers to use globals defined in the same file
        globals = { "vim", "describe", "it", "before_each", "after_each", "assert", "expect" },
    },
}
