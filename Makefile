# Makefile for meow.review.nvim
# Requires: nvim (>= 0.11), stylua, luacheck
# Optional:  luarocks (for bootstrapping busted/nlua)

.PHONY: all test lint format format-check check deps clean

NVIM      ?= nvim
STYLUA    ?= stylua
LUACHECK  ?= luacheck
NLUA      ?= $(HOME)/.luarocks/bin/nlua

LUA_FILES := lua/**/*.lua lua/**/**/*.lua plugin/*.lua tests/**/*.lua scripts/*.lua

# ── Bootstrap test dependencies ───────────────────────────────────────────────

## Install busted + nlua into the user luarocks tree (Lua 5.1)
deps:
	luarocks --lua-version 5.1 install busted
	luarocks --lua-version 5.1 install nlua

# ── Primary targets ───────────────────────────────────────────────────────────

all: check

## Run the busted test suite via nlua (Neovim as Lua interpreter)
test:
	$(NLUA) scripts/run_busted.lua \
		--output TAP \
		tests/spec/

## Run luacheck static analysis
lint:
	$(LUACHECK) lua/ plugin/ tests/ scripts/ --config .luacheckrc

## Format all Lua source files with stylua (modifies in place)
format:
	$(STYLUA) lua/ plugin/ tests/ scripts/

## Check formatting without modifying files (CI-safe)
format-check:
	$(STYLUA) --check lua/ plugin/ tests/ scripts/

## Run lint + format check (CI gate — no modifications)
check: lint format-check

# ── Housekeeping ─────────────────────────────────────────────────────────────

clean:
	rm -rf test-results/ coverage/ deps/
