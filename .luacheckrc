-- .luacheckrc
-- luacheck configuration for meow.review.nvim

-- Neovim global
globals = { "vim" }

-- Ignore unused self in method definitions
self = false

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
        -- Busted globals (describe, it, before_each, etc.)
        globals = {
            "vim",
            "describe",
            "it",
            "before_each",
            "after_each",
            "before_all",
            "after_all",
            "pending",
            "assert",
        },
    },
    ["scripts/**/*.lua"] = {
        globals = { "vim", "arg" },
    },
}
