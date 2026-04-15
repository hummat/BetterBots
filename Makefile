LUA_FILES := $(shell find scripts tests -name '*.lua')
BUSTED_BIN := $(shell command -v busted 2>/dev/null || command -v lua-busted 2>/dev/null || echo "")
ARCH_BUSTED_BIN := $(shell ls /usr/lib/luarocks/rocks-*/busted/*/bin/busted 2>/dev/null | head -n 1)

.PHONY: deps lint format format-check lsp-check check check-ci test doc-check release package tool-info

deps:
	git config core.hooksPath scripts/hooks

LUACHECK_BIN := $(CURDIR)/bin/luacheck

lint:
	$(LUACHECK_BIN) $(LUA_FILES)

format:
	stylua $(LUA_FILES)

format-check:
	stylua --check $(LUA_FILES)

lsp-check:
	lua-language-server --configpath=.luarc.json --check=. --check_format=pretty --logpath=/tmp/luals-betterbots

doc-check:
	@scripts/doc-check.sh

check: format lint lsp-check test doc-check

check-ci: format-check lint lsp-check test doc-check

test:
	@if [ -d tests ]; then \
		if [ -n "$(BUSTED_BIN)" ]; then \
			"$(BUSTED_BIN)"; \
		elif [ -n "$(ARCH_BUSTED_BIN)" ]; then \
			lua "$(ARCH_BUSTED_BIN)"; \
		else \
			echo "No busted runner found on PATH or in /usr/lib/luarocks."; \
			exit 1; \
		fi; \
	else \
		echo "No tests directory; skipping busted."; \
	fi

tool-info:
	@echo "make lint -> $(LUACHECK_BIN)"
	@echo "system luacheck: $$(command -v luacheck || echo missing)"
	@echo "system busted: $$(command -v busted || echo missing)"
	@echo "system lua-busted: $$(command -v lua-busted || echo missing)"
	@echo "arch luarocks busted: $(if $(ARCH_BUSTED_BIN),$(ARCH_BUSTED_BIN),missing)"
	@echo "stylua: $$(command -v stylua || echo missing)"
	@echo "lua-language-server: $$(command -v lua-language-server || echo missing)"

package:
	@rm -f BetterBots.zip
	@cd .. && zip -9 BetterBots/BetterBots.zip \
		BetterBots/BetterBots.mod \
		BetterBots/scripts/mods/BetterBots/*.lua
	@echo "Created BetterBots.zip"
	@unzip -l BetterBots.zip

release:
	@scripts/release.sh $(VERSION)
