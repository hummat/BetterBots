LUA_FILES := $(shell rg --files scripts -g '*.lua')
BUSTED_BIN := $(shell command -v busted 2>/dev/null || command -v lua-busted 2>/dev/null || ls /usr/lib/luarocks/rocks-*/busted/*/bin/busted 2>/dev/null | head -n 1)

.PHONY: deps lint format format-check lsp-check check test release package

deps:
	git config core.hooksPath scripts/hooks

lint:
	luacheck $(LUA_FILES)

format:
	stylua $(LUA_FILES)

format-check:
	stylua --check $(LUA_FILES)

lsp-check:
	lua-language-server --configpath=.luarc.json --check=. --check_format=pretty --logpath=/tmp/luals-betterbots

check: format-check lint lsp-check

test:
	@if [ -d tests ]; then \
		if [ -n "$(BUSTED_BIN)" ]; then \
			lua "$(BUSTED_BIN)"; \
		else \
			echo "No busted runner found on PATH or in /usr/lib/luarocks."; \
			exit 1; \
		fi; \
	else \
		echo "No tests directory; skipping busted."; \
	fi

package:
	@rm -f BetterBots.zip
	@cd .. && zip -9 BetterBots/BetterBots.zip \
		BetterBots/BetterBots.mod \
		BetterBots/scripts/mods/BetterBots/BetterBots.lua \
		BetterBots/scripts/mods/BetterBots/BetterBots_data.lua \
		BetterBots/scripts/mods/BetterBots/BetterBots_localization.lua
	@echo "Created BetterBots.zip"
	@unzip -l BetterBots.zip

release:
	@scripts/release.sh $(VERSION)
