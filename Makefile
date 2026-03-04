LUA_FILES := $(shell rg --files scripts -g '*.lua')
BUSTED_BIN := $(shell command -v busted 2>/dev/null || command -v lua-busted 2>/dev/null || ls /usr/lib/luarocks/rocks-*/busted/*/bin/busted 2>/dev/null | head -n 1)

.PHONY: lint format format-check lsp-check check test

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
