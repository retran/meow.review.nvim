# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-04-18

### Added

- **Formatter registry**: `register_formatter()`, `unregister_formatter()`,
  `list_formatters()` API. Built-in `"markdown"` and `"json"` formatters.
  `default_formatter` config option (default: `"markdown"`).
- **Smart preamble summary block**: `export_summary = true` config option injects
  a `## Summary` section into exported Markdown with file count, annotation
  count, type breakdown, and file list.
- **Resolved annotation state**: `resolved` boolean field on annotations.
  `store.resolve(id)`, `store.resolve_all()`. `store.sorted()` excludes
  resolved annotations by default; `{ include_resolved = true }` opts in.
  `resolve_comment()`, `resolve_all_comments()` on the public API.
  `MeowReviewResolved` highlight group (linked to `Comment`).
  `:MeowReview resolve`, `:MeowReview resolve_all` commands and `<Plug>` maps.
- **Export enhancements**:
  - `export.export()` accepts a `filter` table (`{ file = "path" }`) to
    restrict output to a single file.
  - `export_and_clear(name)` — export then clear on success.
  - `export_current_file(name)` — export only the current buffer's file.
  - `:MeowReview export_and_clear`, `:MeowReview export_file` commands.
  - `<Plug>(MeowReviewExportAndClear)`, `<Plug>(MeowReviewExportFile)` maps.
- **avante.nvim exporter**: auto-registered as `"avante"` when avante.nvim is
  detected. Sends Markdown via `avante.api.ask()`.
- **codecompanion.nvim exporter**: auto-registered as `"codecompanion"` when
  codecompanion.nvim is detected. Sends Markdown via `codecompanion.chat()`.
- **Stale annotation detection** (`validate.lua`): `M.check()` (pure) and
  `M.run()` (interactive). `MeowReviewStale` highlight group.
  `:MeowReview validate` command and `<Plug>(MeowReviewValidate)` map.
- **Status line integration**: `M.status()` returns annotation count string
  suitable for lualine/heirline.
- **Navigation by file/type**: `goto_comment_in_file()`,
  `goto_comment_by_type(type?)`. `:MeowReview goto_file`,
  `:MeowReview goto_type` commands.
- **`utils.lua`**: `resolve_path()` and `ensure_parent_dirs()` helpers.
  Store and export paths default to `.cache/meow-review/`.
- **`auto_gitignore`** config (`"prompt"` | `"always"` | `false`): optionally
  adds the store file to `.gitignore` after first write.
- **Modal improvements**: `modal_width`, `modal_height`, `modal_cycle_key`
  config options. Rich top border label in `open_edit_modal` (`file:line[–end][  symbol]`).
- **Picker adapters**: Snacks → Telescope → fzf-lua → nui.menu fallback chain.
- **Test infrastructure**: busted + nlua, 100 passing tests.

## [0.1.0] - 2026-04-12

Initial release.

[Unreleased]: https://github.com/retran/meow.review.nvim/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/retran/meow.review.nvim/releases/tag/v0.1.0
