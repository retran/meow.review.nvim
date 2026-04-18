# meow.review.nvim — Implementation Plan

Each entry is one focused git commit. The order minimises merge conflicts; each
commit builds cleanly on the previous. Tests ship in the same commit as the feature.

---

## Test framework & devex philosophy

**Framework: mini.test** (from mini.nvim)
- Runs tests inside a real child Neovim process via `MiniTest.new_child_neovim()`.
  No fake `vim.*` stubs needed — actual Neovim APIs work as-is.
- Busted-style `describe` / `it` / `before_each` / `after_each` emulation.
- Headless-friendly stdout reporter → works in CI with zero extra setup.
- Single dependency: `mini.test` (already in the Neovim ecosystem).

**Tooling stack**
| Tool | Purpose |
|------|---------|
| `mini.test` | Test runner (child Neovim process) |
| `stylua` | Formatter (already configured via `.stylua.toml`) |
| `luacheck` | Linter (static analysis, undefined globals, unused vars) |
| `lua-language-server` | Type checking via LuaLS (already configured via `.luarc.json`) |
| `make` | Single entrypoint: `make test`, `make lint`, `make format`, `make check` |
| GitHub Actions | CI: runs `make check` on push / PR |
| `selene` (optional) | Stricter Lua linter with Neovim stdlib awareness |

**Test layout**
```
tests/
  init_spec.lua          -- scripts/minimal_init.lua loading helper
  spec/
    store_spec.lua
    config_spec.lua
    ui_spec.lua
    export_spec.lua
    context_spec.lua
    signs_spec.lua
    validate_spec.lua    -- added in commit 12
    utils_spec.lua       -- added in commit 10
scripts/
  minimal_init.lua       -- minimal Neovim config for test child processes
  run_tests.lua          -- entry point: MiniTest.run()
```

**Coverage target:** every public function in every module has at least one positive
test and one negative/edge-case test. Integration tests (child process) cover the
full add → persist → reload → export round-trip.

---

## Commit 1 — chore: test infrastructure + devex tooling

**Files:** `tests/scripts/minimal_init.lua`, `scripts/run_tests.lua`,
`tests/spec/store_spec.lua` (smoke test only), `Makefile`, `.luacheckrc`,
`.github/workflows/ci.yml`

### What ships

**`scripts/minimal_init.lua`** — minimal Neovim init for child processes:
```lua
vim.opt.rtp:append(".")
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/mini.nvim")
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/nui.nvim")
require("mini.test").setup()
```

**`scripts/run_tests.lua`** — headless entry point:
```lua
require("mini.test").run({ collect = { find_files = function()
    return vim.fn.globpath("tests/spec", "**/*_spec.lua", 1, 1)
end }})
```

**`Makefile`**:
```makefile
.PHONY: test lint format check

test:
	nvim --headless --noplugin -u scripts/minimal_init.lua \
	     -c "lua require('scripts.run_tests')" -c "qa!"

lint:
	luacheck lua/ tests/ --globals vim

format:
	stylua --check lua/ tests/

format-fix:
	stylua lua/ tests/

check: format lint test
```

**`.luacheckrc`**:
```lua
std = "lua51"
globals = { "vim" }
ignore = { "212" }   -- unused argument (common in callbacks)
max_line_length = 120
```

**`.github/workflows/ci.yml`**:
- Installs Neovim (stable + nightly matrix).
- Installs `luacheck` via luarocks.
- Installs `stylua` via cargo / pre-built binary.
- Runs `make check`.

**`tests/spec/store_spec.lua`** — smoke test:
```lua
describe("store", function()
    it("loads without error", function()
        local child = MiniTest.new_child_neovim()
        child:start({ "-u", "scripts/minimal_init.lua" })
        child.lua("require('meow.review.store')")
        child:stop()
    end)
end)
```

---

## Commit 2 — fix(store): collision-resistant ID generation (#15)

**Files:** `lua/meow/review/store.lua`

- Replace `os.time()` with `(vim.uv or vim.loop).hrtime()` in `make_id()`.
- Expand random range to `math.random(0, 2^31 - 1)`.

**Tests added to `tests/spec/store_spec.lua`:**
- `make_id` (exposed via child process): generate 1000 IDs in a tight loop, assert
  all are unique (set membership check).
- Assert ID matches pattern `%d+_%d+`.
- Assert two IDs generated on the same millisecond tick differ.

---

## Commit 3 — refactor(store): expose get_store_path() as public API (#12)

**Files:** `lua/meow/review/store.lua`, `lua/meow/review/health.lua`

- Keep private `resolve_store_path`; add public `M.get_store_path(root)` wrapper.
- `health.lua` `check_store()` calls `store.get_store_path(root)`.

**Tests added to `tests/spec/store_spec.lua`:**
- `get_store_path(root)` with relative `store_path` config → returns `root .. "/" .. path`.
- `get_store_path(root)` with absolute `store_path` → returns path unchanged.
- `get_store_path(root)` with default config → returns path ending in
  `".cache/meow-review/annotations.json"`.

---

## Commit 4 — refactor(ui): extract shared open_modal() (#11)

**Files:** `lua/meow/review/ui.lua`

- Extract private `open_modal(opts)`:
  `top_label`, `initial_type`, `initial_text`, `on_confirm`, `width`, `height`,
  `cycle_key`.
- `open_add_modal` and `open_edit_modal` become thin wrappers.

**Tests added to `tests/spec/ui_spec.lua`** (new file):
- Child process: open add modal, assert popup buffer exists, assert filetype is
  `"markdown"`.
- Child process: open edit modal with pre-filled text, assert buffer lines match
  the annotation text.
- Assert that both add and edit modals share the same dismiss/confirm keybindings
  (inspect mapped keys via `nvim_buf_get_keymap`).

---

## Commit 5 — feat(config): modal_height, modal_width, modal_cycle_key (#6, #7)

**Files:** `lua/meow/review/config/internal.lua`, `lua/meow/review/config/meta.lua`,
`lua/meow/review/ui.lua`

- Add `modal_height = 6`, `modal_width = 64`, `modal_cycle_key = "<C-t>"` to
  defaults and `validate()`.
- `open_modal` reads from config.
- Change cycle mapping from `<Tab>` → `cfg.modal_cycle_key`.
- Update border hint.

**Tests added to `tests/spec/config_spec.lua`** (new file):
- Defaults are correct values and types.
- User values override defaults via `vim.g.meow_review`.
- Invalid `modal_height` (string) causes validation error notify and falls back to
  defaults.
- Invalid `modal_cycle_key` (number) → validation error.
- Child process: open add modal, assert `<Tab>` is NOT mapped in insert mode.
- Child process: open add modal with `modal_cycle_key = "<F2>"`, assert `<F2>` is
  mapped and cycles the type.

---

## Commit 6 — feat(ui): location/context in edit modal top border (#10)

**Files:** `lua/meow/review/ui.lua`

- `open_edit_modal` builds `top_label` using `render_location` and
  `annotation.context`.

**Tests added to `tests/spec/ui_spec.lua`:**
- Child process: open edit modal with `{ lnum=42, context="my_func" }`; assert
  popup border top text contains `"42"` and `"my_func"`.
- Child process: open edit modal without context; assert border top contains line
  number but no `"—"` context suffix.

---

## Commit 7 — fix(ui): clear_all uses vim.ui.select (#9)

**Files:** `lua/meow/review/init.lua`

- Swap `vim.ui.input` for `vim.ui.select`.

**Tests added to `tests/spec/init_spec.lua`** (new file):
- Child process: call `clear_all()` with 0 annotations → notifies "No annotations",
  `vim.ui.select` never called.
- Child process: call `clear_all()` with 2 annotations; simulate selecting "Cancel"
  → annotations still present.
- Child process: simulate selecting "Yes, clear all" → `store.count()` returns 0.

---

## Commit 8 — feat(api): M.status() for statusline integration (#8)

**Files:** `lua/meow/review/init.lua`, `doc/meow-review.txt`

- Add `M.status(opts)` — `opts.format` defaults to `"[{n} comment(s)]"`.
- `{n}` is replaced with annotation count; returns `""` when count is 0.

**Tests added to `tests/spec/init_spec.lua`:**
- `status()` returns `""` when store is empty.
- `status()` returns `"[1 comment(s)]"` with one annotation.
- `status()` returns `"[3 comment(s)]"` with three annotations.
- `status({ format = "{n} issues" })` uses custom format.
- `{n}` placeholder replaced correctly; other text preserved verbatim.

---

## Commit 9 — perf(init): debounce BufEnter sign rendering (#13)

**Files:** `lua/meow/review/init.lua`

- Introduce 50 ms debounce timer in `BufEnter` autocmd.

**Tests added to `tests/spec/init_spec.lua`:**
- Child process: fire `BufEnter` 10 times in rapid succession; assert
  `signs.render_buffer` call count is 1 (spy via override before setup).
- Fire `BufEnter` once, wait > 50 ms; assert render_buffer called exactly once.
- Fire `BufEnter` twice with > 50 ms gap; assert render_buffer called twice.

---

## Commit 10 — refactor(utils): extract resolve_path(); align export default path (#14)

**Files:** `lua/meow/review/utils.lua` (new), `lua/meow/review/store.lua`,
`lua/meow/review/export.lua`, `lua/meow/review/config/internal.lua`

- `utils.lua` exports `M.resolve_path(root, path)` and `M.ensure_parent_dirs(path)`.
- `store.lua` and `export.lua` use `utils`.
- `export_filename` default → `".cache/meow-review/review.md"`.
- `export_to_file` creates parent dirs before writing.

**Tests added to `tests/spec/utils_spec.lua`** (new file):
- `resolve_path(root, "foo/bar")` → `root .. "/foo/bar"`.
- `resolve_path(root, "/abs/path")` → `"/abs/path"`.
- `resolve_path(root, "")` → `root`.
- `ensure_parent_dirs` on a path in a temp dir → directory is created.
- `ensure_parent_dirs` on already-existing dir → no error.

---

## Commit 11 — feat(store): auto-gitignore store file (#1)

**Files:** `lua/meow/review/store.lua`, `lua/meow/review/config/internal.lua`,
`lua/meow/review/config/meta.lua`, `lua/meow/review/health.lua`

- Add `auto_gitignore = "prompt"` config option (`"prompt" | "always" | false`).
- After first `save()`, check `git check-ignore -q <store_path>`:
  - `"always"` → append relative path to `{root}/.gitignore`.
  - `"prompt"` → `vim.ui.select` once per session.
  - `false` → skip.
- `health.lua`: warn if store file is git-tracked.

**Tests added to `tests/spec/store_spec.lua`:**
- `auto_gitignore = "always"`: child process saves an annotation in a temp git
  repo; assert `.gitignore` is created and contains the store path.
- `auto_gitignore = "always"` when `.gitignore` already contains the path → not
  duplicated.
- `auto_gitignore = false` → `.gitignore` never touched.
- `auto_gitignore = "always"` when already git-ignored → no change to `.gitignore`.
- Health check: assert warning appears when store file is tracked.

---

## Commit 12 — feat(store): stale annotation detection (#4)

**Files:** `lua/meow/review/validate.lua` (new), `lua/meow/review/store.lua`,
`lua/meow/review/signs.lua`, `lua/meow/review/init.lua`,
`plugin/meow-review.lua`, `lua/meow/review/config/internal.lua`,
`lua/meow/review/config/meta.lua`

- `validate.lua`: `M.validate(annotations, root)` → sets `ann.stale = true` when
  middle snippet line doesn't match file contents.
- `store.load()` calls validate when `cfg.validate_on_load = true`.
- `MeowReviewStale` hl group linked to `DiagnosticWarn`.
- `:MeowReview validate` subcommand opens picker of stale annotations.
- `validate_on_load = true` config default.

**Tests added to `tests/spec/validate_spec.lua`** (new file):
- Annotation whose middle snippet line matches → `stale = false`.
- Annotation whose middle snippet line doesn't match → `stale = true`.
- Annotation with no snippet → not marked stale.
- All-valid set → returns `{ valid = N, stale = 0 }`.
- Mixed set → counts are correct.
- Child process integration: write temp file, create annotation with matching
  snippet, modify file, reload → stale notify fires.
- Child process: `validate_on_load = false` → no stale notify even with drifted
  annotations.

---

## Commit 13 — feat(ui): per-file and per-type picker filters (#5)

**Files:** `lua/meow/review/init.lua`, `plugin/meow-review.lua`

- `M.goto_comment_in_file()` — filters to current file.
- `M.goto_comment_by_type(type_name)` — filters by type; nil → `vim.ui.select`.
- `:MeowReview goto_file`, `:MeowReview goto_type [TYPE]`.
- `<Plug>(MeowReviewGotoFile)`, `<Plug>(MeowReviewGotoType)`.

**Tests added to `tests/spec/init_spec.lua`:**
- `goto_comment_in_file` with 3 annotations (2 in current file, 1 in other) →
  picker receives exactly 2 items.
- `goto_comment_in_file` with 0 annotations in current file → notifies no annotations.
- `goto_comment_by_type("ISSUE")` with mixed types → picker receives only ISSUEs.
- `goto_comment_by_type(nil)` → `vim.ui.select` is called with type list.
- `:MeowReview goto_file` subcommand is registered and callable.

---

## Commit 14 — feat(ui): Telescope picker adapter (#2)

**Files:** `lua/meow/review/ui.lua`, `lua/meow/review/health.lua`

- Priority: Snacks → Telescope → fzf-lua → nui.menu.
- Build Telescope picker with `pickers.new`, `finders.new_table`,
  `previewers.new_buffer_previewer`; entry maker sets `filename` and `lnum`.
- Add Telescope to optional deps in health check.

**Tests added to `tests/spec/ui_spec.lua`:**
- Child process with Telescope available: `open_picker` → assert Telescope picker
  opened (check window/buf type via `nvim_list_wins` + filetype).
- Child process with Telescope stubbed as unavailable: assert fallback path taken.
- Entry maker produces correct `filename` and `lnum` for an annotation.

---

## Commit 15 — feat(ui): fzf-lua picker adapter (#3)

**Files:** `lua/meow/review/ui.lua`

- After Telescope check, try fzf-lua.
- Lookup table keyed by formatted string maps selection back to annotation.

**Tests added to `tests/spec/ui_spec.lua`:**
- Child process with fzf-lua available: `open_picker` uses fzf-lua path.
- Child process with both Telescope and fzf-lua unavailable: nui.menu fallback.
- Lookup table correctly maps every annotation by display string (unit test, no
  child process needed).

---

## Commit 16 — feat(export): formatter registry with markdown + json built-ins (#19)

**Files:** `lua/meow/review/export.lua`, `lua/meow/review/init.lua`,
`lua/meow/review/config/internal.lua`, `lua/meow/review/config/meta.lua`

- Formatter registry: `register_formatter(name, fn)`, `unregister_formatter(name)`.
- Built-ins: `"markdown"` (existing), `"json"` (raw JSON of annotation list).
- `export.export()` calls `formatters[cfg.formatter](sorted, root)`.
- `formatter = "markdown"` config default.
- `M.register_formatter` / `M.unregister_formatter` exposed in `init.lua`.

**Tests added to `tests/spec/export_spec.lua`** (new file):
- `build_markdown` output contains `"# Code Review"` heading.
- `build_markdown` output contains `"## @"` file sections in correct order.
- `build_markdown` output contains fenced code blocks for annotations with snippets.
- `build_markdown` with empty annotation list → heading only, no file sections.
- JSON formatter returns valid JSON decodable with `vim.json.decode`.
- JSON output contains all SERIAL_FIELDS for each annotation.
- `register_formatter("custom", fn)` → `export(nil)` with `formatter = "custom"`
  calls `fn`.
- `unregister_formatter("custom")` → `export(nil)` warns "unknown formatter".
- Unknown formatter name → warning notify, no crash.
- `formatter = "json"` with clipboard exporter → clipboard contains valid JSON.

---

## Commit 17 — feat(export): smart preamble with summary block (#20)

**Files:** `lua/meow/review/export.lua`, `lua/meow/review/config/internal.lua`,
`lua/meow/review/config/meta.lua`

- Append summary block after `prompt_preamble` when `export_summary = true`:
  ```
  ## Summary
  Files reviewed: 3  |  Annotations: 7 (4 ISSUE, 2 SUGGESTION, 1 NOTE)
  Files: src/foo.lua, src/bar.lua, lib/utils.lua
  ```
- `export_summary = true` config default.

**Tests added to `tests/spec/export_spec.lua`:**
- `export_summary = true` → output contains `"## Summary"` section.
- Summary line counts match actual annotation counts.
- Summary file list matches unique files in annotation set.
- `export_summary = false` → no `"## Summary"` in output.
- Empty `prompt_preamble` + `export_summary = true` → summary still appears.

---

## Commit 18 — feat(store): resolved annotation state (#16)

**Files:** `lua/meow/review/store.lua`, `lua/meow/review/signs.lua`,
`lua/meow/review/init.lua`, `plugin/meow-review.lua`,
`lua/meow/review/config/meta.lua`

- `resolved` boolean field on annotations (default `false`).
- `store.resolve(id)` / `store.resolve_all()`.
- `store.sorted(opts)` — `opts.include_resolved` (default `false`).
- `MeowReviewResolved` hl group (linked to `Comment`).
- `:MeowReview resolve`, `:MeowReview resolve_all`.
- `<Plug>(MeowReviewResolve)`, `<Plug>(MeowReviewResolveAll)`.

**Tests added to `tests/spec/store_spec.lua`:**
- `resolve(id)` sets `resolved = true` and persists to JSON.
- `resolve(unknown_id)` → returns false, no error.
- `resolve_all()` marks all annotations resolved.
- `sorted()` (default) excludes resolved annotations.
- `sorted({ include_resolved = true })` includes resolved annotations.
- Round-trip: save resolved annotation, reload, assert `resolved = true` preserved.
- Old JSON without `resolved` field → loads cleanly, `resolved` defaults to false.

**Tests added to `tests/spec/init_spec.lua`:**
- `resolve_comment()` at cursor with no annotation → warns.
- `resolve_comment()` at cursor with one annotation → that annotation is resolved.
- `resolve_all_comments()` → all annotations resolved after confirmation.

---

## Commit 19 — feat(api): export_and_clear, export_current_file (#17, #18)

**Files:** `lua/meow/review/init.lua`, `lua/meow/review/export.lua`,
`plugin/meow-review.lua`

- `export.export(name, filter)` — `filter.file` restricts to one file.
- `M.export_and_clear(name)` — export then clear on success.
- `M.export_current_file(name)`.
- `:MeowReview export_and_clear [exporter]`, `:MeowReview export_file [exporter]`.
- `<Plug>(MeowReviewExportAndClear)`, `<Plug>(MeowReviewExportFile)`.

**Tests added to `tests/spec/export_spec.lua`:**
- `export(name, { file = "src/foo.lua" })` only includes annotations for that file.
- `export(name, { file = "nonexistent.lua" })` → warns no annotations.

**Tests added to `tests/spec/init_spec.lua`:**
- `export_and_clear`: successful export → `store.count()` is 0 afterwards.
- `export_and_clear`: exporter raises error → annotations NOT cleared.
- `export_current_file` passes correct file filter (spy on `exp().export`).

---

## Commit 20 — feat(export): avante.nvim and codecompanion.nvim exporters (#21)

**Files:** `lua/meow/review/export.lua`, `doc/meow-review.txt`

- In `setup_builtins()`: auto-register `"avante"` and `"codecompanion"` if detected.

**Tests added to `tests/spec/export_spec.lua`:**
- Child process with `avante` stubbed in `package.loaded`: assert `"avante"`
  exporter is registered after `setup_builtins()`.
- Child process without `avante`: assert `"avante"` is NOT in `export.list()`.
- Same for `codecompanion`.
- Calling the `"avante"` exporter invokes `avante.api.ask` with the markdown string.

---

## Commit 21 — docs: update help file, README, CHANGELOG

**Files:** `doc/meow-review.txt`, `README.md`, `CHANGELOG.md`

- Document all new config options.
- Document all new commands and `<Plug>` maps.
- Document new public API functions.
- Add statusline integration examples (lualine, heirline).
- Add avante / codecompanion usage examples.
- Update CHANGELOG with all changes since v0.1.0.

---

## Commit order summary

| Commit | Item(s) | Type | Modules touched |
|--------|---------|------|-----------------|
| 1 | — | chore | `tests/`, `Makefile`, `.luacheckrc`, CI |
| 2 | #15 | fix | `store` |
| 3 | #12 | refactor | `store`, `health` |
| 4 | #11 | refactor | `ui` |
| 5 | #6, #7 | feat | `config`, `ui` |
| 6 | #10 | feat | `ui` |
| 7 | #9 | fix | `init` |
| 8 | #8 | feat | `init`, `doc` |
| 9 | #13 | perf | `init` |
| 10 | #14 | refactor | `utils` (new), `store`, `export`, `config` |
| 11 | #1 | feat | `store`, `config`, `health` |
| 12 | #4 | feat | `validate` (new), `store`, `signs`, `init`, `plugin`, `config` |
| 13 | #5 | feat | `init`, `plugin` |
| 14 | #2 | feat | `ui`, `health` |
| 15 | #3 | feat | `ui` |
| 16 | #19 | feat | `export`, `init`, `config` |
| 17 | #20 | feat | `export`, `config` |
| 18 | #16 | feat | `store`, `signs`, `init`, `plugin`, `config` |
| 19 | #17, #18 | feat | `init`, `export`, `plugin` |
| 20 | #21 | feat | `export`, `doc` |
| 21 | — | docs | `doc`, `README`, `CHANGELOG` |
