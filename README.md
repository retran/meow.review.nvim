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

<strong>meow.review.nvim — Annotate Code, Guide Your AI</strong>

</div>

Ever left a mental note about AI-generated code only to lose track of it? `meow.review.nvim` lets you **leave typed, persistent review comments directly in Neovim** and export them as structured Markdown so your AI agent knows exactly what to fix and where. Think of it as a sticky-note system for your editor — except each note survives restarts, tracks position drift, and speaks fluent AI prompt.

Part of the [project meow](https://github.com/retran/meow) plugin family.

---

## Screenshots

> _Screenshots coming soon._

---

## Key Features

- **Typed annotations** — ISSUE, SUGGESTION, NOTE with distinct icons and highlight groups (fully customizable)
- **Contextual capture** — Treesitter symbol name (function/class) attached to each annotation
- **Hunk detection** — automatically associates annotations with git hunks (gitsigns) or vimdiff hunks
- **JSON persistence** — store survives Neovim restarts; default path `.cache/meow-review/annotations.json`
- **Pluggable export** — register custom exporters; built-in `file`, `file_prompt`, and `clipboard` targets included
- **Formatter registry** — built-in `markdown` and `json` formatters; register custom formatters
- **avante.nvim / codecompanion.nvim** — auto-registered exporters when those plugins are detected
- **Smart export** — `## Summary` preamble block, file filter (`export_current_file`), export-and-clear workflow
- **Resolved state** — mark annotations resolved; resolved annotations excluded from export by default
- **Stale detection** — validate annotations against current file; highlight stale ones
- **Navigation** — jump forward/backward between annotations across files; filter by file or type
- **Statusline integration** — `status()` returns annotation count string for lualine/heirline
- **Sign column** — per-type signs track position drift as buffers are edited (extmarks)
- **`:checkhealth`** — `meow.review` health check reports dependency status, config, and exporters

---

## Prerequisites

### Required

| Requirement | Details |
| ----------- | ------- |
| **Neovim** | ≥ 0.11.0 |
| **Dependencies** | [nui.nvim](https://github.com/MunifTanjim/nui.nvim) |

### Optional

| Dependency | Details |
| ---------- | ------- |
| [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | Symbol context in annotations |
| [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) | Git hunk association |
| [snacks.nvim](https://github.com/folke/snacks.nvim) | Enhanced picker UI (falls back to nui.menu) |
| [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) | Alternative picker UI |
| [fzf-lua](https://github.com/ibhagwan/fzf-lua) | Alternative picker UI |
| [avante.nvim](https://github.com/yetone/avante.nvim) | Auto-registered `avante` exporter |
| [codecompanion.nvim](https://github.com/olimorris/codecompanion.nvim) | Auto-registered `codecompanion` exporter |

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
            -- Your custom configuration goes here
        })
    end,
    keys = {
        { "<leader>ra", "<Plug>(MeowReviewAdd)",            mode = { "n", "v" }, desc = "Add Review Comment" },
        { "<leader>rd", "<Plug>(MeowReviewDelete)",         mode = { "n", "v" }, desc = "Delete Review Comment" },
        { "<leader>re", "<Plug>(MeowReviewEdit)",           desc = "Edit Review Comment" },
        { "<leader>rv", "<Plug>(MeowReviewView)",           desc = "View Review Comment" },
        { "<leader>rE", "<Plug>(MeowReviewExport)",         desc = "Export Review" },
        { "<leader>rX", "<Plug>(MeowReviewExportAndClear)", desc = "Export and Clear" },
        { "<leader>rf", "<Plug>(MeowReviewExportFile)",     desc = "Export Current File" },
        { "<leader>rc", "<Plug>(MeowReviewClear)",          desc = "Clear All Comments" },
        { "<leader>rg", "<Plug>(MeowReviewGoto)",           desc = "Go to Review Comment" },
        { "<leader>rG", "<Plug>(MeowReviewGotoFile)",       desc = "Go to Comment in File" },
        { "<leader>rt", "<Plug>(MeowReviewGotoType)",       desc = "Go to Comment by Type" },
        { "<leader>rR", "<Plug>(MeowReviewResolve)",        desc = "Resolve Comment" },
        { "<leader>rA", "<Plug>(MeowReviewResolveAll)",     desc = "Resolve All Comments" },
        { "<leader>rr", "<Plug>(MeowReviewReload)",         desc = "Reload Review" },
        { "]r",         "<Plug>(MeowReviewNext)",           desc = "Next Review Comment" },
        { "[r",         "<Plug>(MeowReviewPrev)",           desc = "Previous Review Comment" },
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

Add to your Neovim configuration:

```lua
require("meow.review").setup({
    -- Your custom configuration goes here
})
```

### Quick Start

1. Open any file in a project directory.
2. Position the cursor on a line (or make a visual selection) to annotate.
3. Run `:MeowReview add` or press your mapped key.
4. In the modal, press `<C-t>` to cycle the annotation type, type your comment, press `<C-s>` to save.
5. The annotation appears in the sign column.
6. Run `:MeowReview export` to export all annotations as Markdown.

---

## Configuration and Mappings

### Default Configuration

Pass a configuration table to `setup()`. All keys are optional — unset keys use the defaults shown below.

```lua
require("meow.review").setup({
    -- Lines of source context captured above and below the annotated range.
    -- Set to 0 to disable snippet capture.
    context_lines = 3,

    -- Built-in exporters to disable.
    -- Available: "file", "file_prompt", "clipboard",
    -- "avante" (auto-registered when avante.nvim is present),
    -- "codecompanion" (auto-registered when codecompanion.nvim is present).
    disabled_exporters = {},

    -- Default exporter used by :MeowReview export (with no name given).
    default_exporter = "clipboard",

    -- Default formatter. Built-ins: "markdown", "json".
    default_formatter = "markdown",

    -- Filename written by the `file` and `file_prompt` exporters.
    -- Relative paths are resolved against the project root.
    export_filename = ".review.md",

    -- Path to the annotation store JSON file.
    -- Relative paths are resolved against the project root; absolute paths are used as-is.
    -- Parent directories are created automatically.
    store_path = ".cache/meow-review/annotations.json",

    -- Modal popup dimensions.
    modal_width  = 64,
    modal_height = 6,

    -- Insert-mode key to cycle annotation type in the add/edit modal.
    modal_cycle_key = "<C-t>",

    -- Whether to add the store file to .gitignore.
    -- "always": silently add.  "prompt" (default): ask once.  false: disable.
    auto_gitignore = "prompt",

    -- Text inserted after the document heading in the exported Markdown.
    -- Instructs the AI agent to apply each annotation as a targeted, minimal fix.
    -- Set to "" to omit the preamble entirely.
    prompt_preamble = "The following annotations were left during a code review. "
        .. "For each annotation, read the code snippet and comment carefully, "
        .. "then apply the requested fix directly to the file. "
        .. "Prefer minimal, targeted edits. Do not refactor unrelated code.",

    -- Inject a ## Summary block listing file count, annotation count, and file list.
    export_summary = true,

    -- Custom annotation types. Replaces the built-in ISSUE / SUGGESTION / NOTE set.
    -- To keep a built-in type, include it explicitly in this table.
    annotation_types = nil,   -- default: { ISSUE = …, SUGGESTION = …, NOTE = … }

    -- Tab-cycling order for the add-comment modal.
    -- Defaults to { "ISSUE", "SUGGESTION", "NOTE" } or sorted keys of annotation_types.
    annotation_type_order = nil,
})
```

### `vim.g.meow_review` (alternative)

Set configuration before the plugin loads:

```lua
vim.g.meow_review = {
    context_lines     = 5,
    disabled_exporters = { "clipboard" },
    default_exporter  = "file",
    export_filename   = ".review.md",
    prompt_preamble   = "Fix the issues below. Keep changes minimal.",
}
```

### Annotation Types

Three annotation types are built in. Providing `annotation_types` in `setup()` **replaces the entire set** — include built-in types explicitly to keep them.

#### Add a custom type alongside the defaults

```lua
require("meow.review").setup({
    annotation_types = {
        ISSUE      = { icon = "", hl = "DiagnosticError", label = "ISSUE" },
        SUGGESTION = { icon = "", hl = "DiagnosticWarn",  label = "SUGGESTION" },
        NOTE       = { icon = "", hl = "DiagnosticInfo",  label = "NOTE" },
        QUESTION   = { icon = "?", hl = "DiagnosticHint", label = "QUESTION" },
    },
    annotation_type_order = { "ISSUE", "SUGGESTION", "NOTE", "QUESTION" },
})
```

Each annotation type entry accepts:

| Field | Type | Default | Description |
| ----- | ---- | ------- | ----------- |
| `icon` | `string` | built-in or `""` | Sign column character |
| `hl` | `string` | built-in or `"Normal"` | Highlight group for the sign |
| `label` | `string` | key name | Label used in the exported Markdown heading |
| `sign_name` | `string` | `"MeowReview" .. key` | Neovim sign name (auto-derived if omitted) |

### Keymaps

The plugin ships with `<Plug>` mappings only — no default keymaps are set. Map them however you like.

| `<Plug>` Mapping | Suggested Key | Mode | Description |
| ---------------- | ------------- | ---- | ----------- |
| `(MeowReviewAdd)` | `<leader>ra` | `n`, `v` | Add annotation at cursor / visual selection |
| `(MeowReviewDelete)` | `<leader>rd` | `n`, `v` | Delete annotation at cursor |
| `(MeowReviewEdit)` | `<leader>re` | `n` | Edit annotation at cursor |
| `(MeowReviewView)` | `<leader>rv` | `n` | View annotation popup at cursor |
| `(MeowReviewExport)` | `<leader>rE` | `n` | Export all annotations |
| `(MeowReviewExportAndClear)` | `<leader>rX` | `n` | Export then clear all annotations |
| `(MeowReviewExportFile)` | `<leader>rf` | `n` | Export annotations for current file only |
| `(MeowReviewClear)` | `<leader>rc` | `n` | Clear all annotations (with confirmation) |
| `(MeowReviewGoto)` | `<leader>rg` | `n` | Open picker — jump to any annotation |
| `(MeowReviewGotoFile)` | `<leader>rG` | `n` | Open picker — jump to annotation in current file |
| `(MeowReviewGotoType)` | `<leader>rt` | `n` | Open picker — jump to annotation by type |
| `(MeowReviewResolve)` | `<leader>rR` | `n` | Resolve annotation at cursor |
| `(MeowReviewResolveAll)` | `<leader>rA` | `n` | Resolve all annotations (with confirmation) |
| `(MeowReviewReload)` | `<leader>rr` | `n` | Reload annotations from JSON |
| `(MeowReviewNext)` | `]r` | `n` | Jump to next annotation |
| `(MeowReviewPrev)` | `[r` | `n` | Jump to previous annotation |

### Commands

| Command | Description |
| ------- | ----------- |
| `:MeowReview add` | Add annotation at cursor or visual selection |
| `:MeowReview delete` | Delete annotation at cursor |
| `:MeowReview edit` | Edit annotation at cursor |
| `:MeowReview view` | View annotation popup at cursor |
| `:MeowReview export [name]` | Run the named exporter (default: `clipboard`) |
| `:MeowReview export_and_clear [name]` | Export then clear all annotations |
| `:MeowReview export_file [name]` | Export annotations for the current file |
| `:MeowReview clear` | Clear all annotations (with confirmation) |
| `:MeowReview goto` | Open picker — jump to any annotation |
| `:MeowReview goto_file` | Open picker — jump to annotation in current file |
| `:MeowReview goto_type [type]` | Open picker — jump to annotation by type |
| `:MeowReview resolve` | Resolve annotation at cursor |
| `:MeowReview resolve_all` | Resolve all annotations (with confirmation) |
| `:MeowReview reload` | Reload annotations from JSON |
| `:MeowReview validate` | Check for stale annotations |
| `:MeowReview next` | Jump to next annotation |
| `:MeowReview prev` | Jump to previous annotation |

Exporter names are tab-completed.

### Modal Keys

#### Add / Edit modal

| Key | Mode | Action |
| --- | ---- | ------ |
| `<C-t>` (configurable) | insert | Cycle annotation type |
| `<C-s>` | insert, normal | Confirm and save |
| `<CR>` | normal | Confirm and save |
| `<Esc>` | insert | Switch to normal mode |
| `<Esc>` / `q` | normal | Cancel |
| `<C-c>` | insert | Cancel |

---

## Export System

The export system is **pluggable**. Three built-in exporters are registered by `setup()`:

| Name | Behaviour |
| ---- | --------- |
| `clipboard` | Copies Markdown to the system clipboard (`+` register) — **default** |
| `file` | Writes to the configured `export_filename` in the project root |
| `file_prompt` | Prompts for a filename (pre-filled with `export_filename`), then writes |

Run the configured `default_exporter`:

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

Trigger it:

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

Sends the review to the active zellij pane so opencode can act on it immediately.

```lua
require("meow.review").register_exporter("zellij", function(markdown, _root)
    local tmp = os.tmpname() .. ".md"
    local f = io.open(tmp, "w")
    if not f then
        vim.notify("MeowReview: zellij: could not write temp file", vim.log.levels.ERROR)
        return
    end
    f:write(markdown)
    f:close()

    vim.fn.system({
        "zellij", "run", "--",
        "sh", "-c",
        "cat " .. vim.fn.shellescape(tmp)
            .. " | opencode --stdin && rm "
            .. vim.fn.shellescape(tmp),
    })
end)
```

```vim
:MeowReview export zellij
```

### Export Format

The Markdown is structured for AI agent consumption — each file gets a `## @file` section, and each annotation heading is machine-parseable:

````markdown
# Code Review — 2026-04-12

The following annotations were left during a code review. For each annotation,
read the code snippet and comment carefully, then apply the requested fix
directly to the file. Prefer minimal, targeted edits.

## Summary
Files reviewed: 1  |  Annotations: 1 (ISSUE: 1)
Files: path/to/file.lua

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

Code style:
- `.stylua.toml`: 4-space indent, 120-column, `AutoPreferDouble` quotes
- Full MIT license headers in all Lua files
- LuaLS annotations (`---@param`, `---@return`, `---@class`)
- `@file:` and `@brief:` doc comment tags

---

## License

Licensed under the MIT License. See [`LICENSE`](LICENSE) for details.

---

## Acknowledgments

`meow.review.nvim` would not be possible without these amazing projects:

- [Neovim](https://neovim.io/)
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim) — UI components
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) — symbol context
- [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) — hunk detection

---

### Author

`meow.review.nvim` is developed by Andrew Vasilyev with help from GitHub Copilot and OpenCode, and feline assistants Sonya Blade, Mila, and Marcus Fenix.

---

<div align="center">

**Happy coding with project meow! 🐱**

Made with ❤️ by Andrew Vasilyev with help from GitHub Copilot and OpenCode, and feline assistants Sonya Blade, Mila, and Marcus Fenix.

[Report Bug](https://github.com/retran/meow.review.nvim/issues) ·
[Request Feature](https://github.com/retran/meow.review.nvim/issues) ·
[Contribute](https://github.com/retran/meow.review.nvim/pulls)

</div>
