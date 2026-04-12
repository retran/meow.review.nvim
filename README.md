# 🐱 meow.review.nvim

> A purr-fectly structured way to annotate and review code in Neovim.

<div align="center">

![Neovim](https://img.shields.io/badge/neovim-%23019733.svg?style=for-the-badge&logo=neovim&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue.svg?style=for-the-badge)
![GitHub stars](https://img.shields.io/github/stars/retran/meow.review.nvim?style=for-the-badge)
![GitHub forks](https://img.shields.io/github/forks/retran/meow.review.nvim?style=for-the-badge)

</div>

<div align="center">

<img src="https://github.com/retran/meow/raw/dev/assets/icon_small.png" alt="Meow Logo" width="200" /><br />

<strong>meow.review.nvim - Annotate Code, Guide Your AI</strong>

</div>

Ever find yourself leaving scattered notes for your AI coding agent, only to lose track of what needs fixing where? `meow.review.nvim` is here to help. It lets you annotate AI-generated code with structured, typed review comments directly in Neovim — then export them as clean Markdown so your AI agent knows exactly what to fix and where. **`meow.review.nvim` turns your review notes into precise, actionable instructions for AI-assisted development**.

---

## Key Features

- **Typed annotations** — ISSUE, SUGGESTION, NOTE with distinct icons and highlight groups (fully customizable)
- **Contextual capture** — Treesitter symbol name (function/class) attached to each annotation
- **Hunk detection** — automatically associates annotations with git hunks (gitsigns) or vimdiff hunks
- **JSON persistence** — `.meow-review.json` at the project root; survives Neovim restarts
- **Pluggable export** — register custom exporters; built-in `file` and `clipboard` targets included
- **Navigation** — jump forward/backward between annotations across files
- **Sign column** — per-type signs track position drift as buffers are edited (extmarks)
- **`:checkhealth`** — `meow.review` health check reports dependency status, config, and exporters

---

## Prerequisites

### Required

| Requirement | Details |
| ----------- | ------- |
| **Neovim** | ≥ 0.8.0 |
| **Dependencies** | [nui.nvim](https://github.com/MunifTanjim/nui.nvim) |

### Optional

| Dependency | Details |
| ---------- | ------- |
| [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | Symbol context in annotations |
| [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) | Git hunk association |
| [snacks.nvim](https://github.com/folke/snacks.nvim) | Enhanced picker UI |

---

## Getting Started

### Installation

Install `meow.review.nvim` using your favorite plugin manager.

#### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    "retran/meow.review.nvim",
    dependencies = { "MunifTanjim/nui.nvim" },
    event = "VeryLazy",
    config = function()
        require("meow.review").setup({
            context_lines = 3,
        })
    end,
    keys = {
        { "<leader>ra", "<Plug>(MeowReviewAdd)",     mode = { "n", "v" }, desc = "Add Review Comment" },
        { "<leader>rd", "<Plug>(MeowReviewDelete)",  mode = { "n", "v" }, desc = "Delete Review Comment" },
        { "<leader>rv", "<Plug>(MeowReviewView)",    desc = "View Review Comment" },
        { "<leader>re", "<Plug>(MeowReviewExport)",  desc = "Export Review" },
        { "<leader>rc", "<Plug>(MeowReviewClear)",   desc = "Clear All Comments" },
        { "<leader>rS", "<Plug>(MeowReviewSummary)", desc = "Review Summary" },
        { "<leader>rr", "<Plug>(MeowReviewReload)",  desc = "Reload Review" },
        { "]r",         "<Plug>(MeowReviewNext)",    desc = "Next Review Comment" },
        { "[r",         "<Plug>(MeowReviewPrev)",    desc = "Previous Review Comment" },
    },
}
```

#### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
    "retran/meow.review.nvim",
    requires = { "MunifTanjim/nui.nvim" },
    config = function()
        require("meow.review").setup({})
    end,
}
```

#### [rocks.nvim](https://github.com/lumen-oss/rocks.nvim)

```vim
:Rocks install meow.review.nvim
```

The dependency (nui.nvim) will be automatically installed and managed.
Then add to your Neovim configuration:

```lua
require("meow.review").setup({
    -- Your custom configuration goes here
})
```

### Quick Start

The plugin provides the `:MeowReview` command to manage annotations.

- **Add annotation at cursor:** `:MeowReview add`
- **Export all annotations:** `:MeowReview export`
- **Export to a specific target:** `:MeowReview export file`
- **Jump to next annotation:** `:MeowReview next`
- **View annotation summary:** `:MeowReview summary`

---

## Configuration and Mappings

### Default Configuration

You can customize the plugin by passing a configuration table to the `setup` function. Here are the defaults:

```lua
require("meow.review").setup({
    -- Number of context lines captured above and below the annotated range.
    -- Set to 0 to disable snippet capture.
    context_lines = 3,

    -- Built-in exporters to disable. Available: "file", "file_prompt", "clipboard".
    disabled_exporters = {},

    -- Default exporter used by :MeowReview export (no name given).
    default_exporter = "clipboard",

    -- Filename written by the `file` and `file_prompt` exporters.
    export_filename = ".meow-review.md",

    -- Text inserted after the document heading in the exported Markdown.
    -- The default instructs the AI agent to apply each annotation as a
    -- targeted, minimal fix. Set to "" to omit the preamble entirely.
    prompt_preamble = "The following annotations were left during a code review. "
        .. "For each annotation, read the code snippet and comment carefully, "
        .. "then apply the requested fix directly to the file. "
        .. "Prefer minimal, targeted edits. Do not refactor unrelated code.",

    -- Custom annotation types. When provided, replaces/extends the built-in
    -- ISSUE / SUGGESTION / NOTE set. Keys are the type names used in
    -- annotations and in the exported Markdown heading.
    -- Each entry can override: icon, hl (highlight group), label, sign_name.
    -- Missing fields fall back to the built-in defaults for that key (if any)
    -- or to sensible values ("", "Normal", key, "MeowReview"..key).
    annotation_types = nil,   -- default: { ISSUE = …, SUGGESTION = …, NOTE = … }

    -- Tab-cycling order for the add-comment modal. Must contain valid keys
    -- from annotation_types (or the built-in set when annotation_types is nil).
    -- Defaults to sorted keys when annotation_types is set, or the built-in
    -- order (ISSUE → SUGGESTION → NOTE) when annotation_types is nil.
    annotation_type_order = nil,  -- default: { "ISSUE", "SUGGESTION", "NOTE" }
})
```

### `vim.g.meow_review` (alternative)

```lua
vim.g.meow_review = {
    context_lines = 5,
    disabled_exporters = { "clipboard" },
    default_exporter = "file",
    export_filename = ".review.md",
    prompt_preamble = "Fix the issues below. Keep changes minimal.",
}
```

### Annotation Types

The built-in annotation types (ISSUE, SUGGESTION, NOTE) can be fully replaced or
extended through the `annotation_types` and `annotation_type_order` config keys.

#### Keeping the defaults (no config needed)

```lua
require("meow.review").setup({})
-- ISSUE, SUGGESTION, NOTE — built-in icons and highlight groups
```

#### Adding a custom type alongside the defaults

```lua
require("meow.review").setup({
    annotation_types = {
        ISSUE      = { icon = "", hl = "DiagnosticError",   label = "ISSUE" },
        SUGGESTION = { icon = "", hl = "DiagnosticWarn",    label = "SUGGESTION" },
        NOTE       = { icon = "", hl = "DiagnosticInfo",    label = "NOTE" },
        QUESTION   = { icon = "?", hl = "DiagnosticHint",  label = "QUESTION" },
    },
    annotation_type_order = { "ISSUE", "SUGGESTION", "NOTE", "QUESTION" },
})
```

#### Replacing the entire type set

```lua
require("meow.review").setup({
    annotation_types = {
        BUG      = { icon = "", hl = "DiagnosticError", label = "BUG" },
        FEEDBACK = { icon = "", hl = "DiagnosticInfo",  label = "FEEDBACK" },
    },
    annotation_type_order = { "BUG", "FEEDBACK" },
})
```

Each annotation type entry accepts:

| Field | Type | Default | Description |
| ----- | ---- | ------- | ----------- |
| `icon` | `string` | built-in icon or `""` | Sign column character |
| `hl` | `string` | built-in hl or `"Normal"` | Highlight group for the sign |
| `label` | `string` | key name | Label used in the exported Markdown heading |
| `sign_name` | `string` | `"MeowReview" .. key` | Internal Neovim sign name |


### Keymaps

The plugin ships with `<Plug>` mappings only — no default keymaps are set automatically.

| `<Plug>` Mapping | Suggested Key | Mode | Description |
| ---------------- | ------------- | ---- | ----------- |
| `(MeowReviewAdd)` | `<leader>ra` | `n`, `v` | Add annotation at cursor / visual selection |
| `(MeowReviewDelete)` | `<leader>rd` | `n`, `v` | Delete annotation at cursor |
| `(MeowReviewView)` | `<leader>rv` | `n` | View annotation popup at cursor |
| `(MeowReviewExport)` | `<leader>re` | `n` | Export all annotations to Markdown |
| `(MeowReviewClear)` | `<leader>rc` | `n` | Clear all annotations (with confirmation) |
| `(MeowReviewSummary)` | `<leader>rS` | `n` | Open summary picker |
| `(MeowReviewReload)` | `<leader>rr` | `n` | Reload from `.meow-review.json` |
| `(MeowReviewNext)` | `]r` | `n` | Jump to next annotation |
| `(MeowReviewPrev)` | `[r` | `n` | Jump to previous annotation |

### Commands

| Command | Description |
| ------- | ----------- |
| `:MeowReview add` | Add annotation at cursor |
| `:MeowReview delete` | Delete annotation at cursor |
| `:MeowReview view` | View annotation popup |
| `:MeowReview export` | Run the default exporter (`clipboard` unless configured) |
| `:MeowReview export file` | Write to `export_filename` in the project root |
| `:MeowReview export file_prompt` | Prompt for filename, then write |
| `:MeowReview export clipboard` | Copy to system clipboard |
| `:MeowReview export <name>` | Run a custom exporter by name |
| `:MeowReview clear` | Clear all annotations |
| `:MeowReview summary` | Open summary picker |
| `:MeowReview reload` | Reload from JSON |
| `:MeowReview next` | Next annotation |
| `:MeowReview prev` | Previous annotation |

Exporter names are tab-completed.

### Add Modal

When adding a comment, a modal opens with:

| Key | Action |
| --- | ------ |
| `<Tab>` | Cycle annotation type (ISSUE → SUGGESTION → NOTE → … by default) |
| `<CR>` | Confirm and save the annotation |
| `<Esc>` / `<C-c>` | Cancel |

---

## Export System

The export system is **pluggable**. Three built-in exporters are registered by `setup()`:

| Name | Behaviour |
| ---- | --------- |
| `clipboard` | Copies Markdown to the system clipboard (`+` register) — **default** |
| `file` | Writes to the configured `export_filename` in the project root |
| `file_prompt` | Prompts for a filename (pre-filled with `export_filename`), then writes |

`:MeowReview export` runs the configured `default_exporter` (`clipboard` unless overridden):

```vim
:MeowReview export
```

Target a specific exporter by name:

```vim
:MeowReview export file
:MeowReview export file_prompt
:MeowReview export clipboard
```

### Custom Exporters

Register any function as an exporter after `setup()`:

```lua
---@type meow.review.ExporterFn
require("meow.review").register_exporter("my_exporter", function(markdown, root)
    -- markdown: full Markdown string
    -- root:     absolute project root path
end)
```

Trigger it with:

```vim
:MeowReview export my_exporter
```

Unregister at runtime:

```lua
require("meow.review").unregister_exporter("clipboard")
```

### Disable a Built-in Exporter

```lua
require("meow.review").setup({
    disabled_exporters = { "clipboard" },
})
```

### Example: zellij + opencode

This exporter sends the review to the active zellij pane so that opencode can
act on it immediately.

```lua
require("meow.review").register_exporter("zellij", function(markdown, _root)
    -- Write to a temp file to avoid shell-quoting issues with long content
    local tmp = os.tmpname() .. ".md"
    local f = io.open(tmp, "w")
    if not f then
        vim.notify("[meow-review] zellij: could not write temp file", vim.log.levels.ERROR)
        return
    end
    f:write(markdown)
    f:close()

    vim.fn.system({
        "zellij", "run", "--",
        "sh", "-c",
        "cat " .. vim.fn.shellescape(tmp) .. " | opencode --stdin && rm " .. vim.fn.shellescape(tmp),
    })
end)
```

Then run:

```vim
:MeowReview export zellij
```

### Export Format

The Markdown is structured for AI agent consumption — each file gets a
`## @file` section, and each annotation heading is machine-parseable:

````markdown
# Code Review — 2026-04-12

The following annotations were left during a code review. For each annotation,
read the code snippet and comment carefully, then apply the requested fix
directly to the file. Prefer minimal, targeted edits.

## @path/to/file.lua

### [ISSUE] path/to/file.lua — line 42 — `M.setup`

```lua
39: -- context line
40: -- context line
41: -- context line
42: local broken = thing()   -- annotated line
43: -- context line
```

Your comment text here.
````

---

## Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request.

- Report bugs and issues
- Suggest new features
- Improve documentation
- Submit pull requests

---

## License

Licensed under the MIT License. See [`LICENSE`](LICENSE) for details.

---

## Acknowledgments

`meow.review.nvim` would not be possible without these amazing projects:

- [Neovim](https://neovim.io/)
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim) for the wonderful UI components
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) for symbol context
- [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) for hunk detection

---

### Author

`meow.review.nvim` is developed by Andrew Vasilyev with help from GitHub Copilot, OpenCode, and feline assistants Sonya Blade, Mila, and Marcus Fenix.

---

<div align="center">

**Happy coding with `project meow`! 🐱**

Made with ❤️ by Andrew Vasilyev with help from GitHub Copilot and OpenCode, and feline assistants Sonya Blade, Mila, and Marcus Fenix.

[Report Bug](https://github.com/retran/meow.review.nvim/issues) ·
[Request Feature](https://github.com/retran/meow.review.nvim/issues) ·
[Contribute](https://github.com/retran/meow.review.nvim/pulls)

</div>
