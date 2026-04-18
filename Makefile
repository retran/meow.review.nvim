# Makefile for meow.review.nvim
# Requires: nvim, stylua, luacheck (optional: luarocks)

.PHONY: all test lint format check clean

NVIM ?= nvim
STYLUA ?= stylua
LUACHECK ?= luacheck

LUA_FILES := lua/**/*.lua lua/**/**/*.lua plugin/**/*.lua

# ── Targets ──────────────────────────────────────────────────────────────────

all: check

## Run the full test suite with mini.test (headless Neovim)
test:
	$(NVIM) --headless --noplugin -u scripts/minimal_init.lua \
		-c "lua require('mini.test').run_file_test()" \
		-c "lua vim.cmd('qa!')" \
		2>&1 | tee /dev/stderr; \
	$(NVIM) --headless --noplugin -u scripts/minimal_init.lua \
		-l scripts/run_tests.lua

## Run luacheck static analysis
lint:
	$(LUACHECK) lua/ plugin/ --config .luacheckrc

## Format all Lua source files with stylua
format:
	$(STYLUA) lua/ plugin/ tests/

## Check formatting without modifying files
format-check:
	$(STYLUA) --check lua/ plugin/ tests/

## Run lint + format check (CI-safe, no modifications)
check: lint format-check

clean:
	rm -rf test-results/ coverage/
