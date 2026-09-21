# Утилита мутационного тестирования: установка окружения и проверки.

VENV := .venv
PYTHON ?= python3

.PHONY: help
help: ## Список целей
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN { FS = ":.*?## " } { printf "  %-14s %s\n", $$1, $$2 }'

.PHONY: setup
setup: $(VENV)/bin/mutate .rocks/bin/luatest ## Поставить universalmutator и luatest для самопроверки

$(VENV)/bin/mutate: requirements.txt
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/pip install --quiet --requirement requirements.txt
	touch $@

# luatest нужен только самопроверке: она гоняет проверки образцов.
.rocks/bin/luatest:
	tt rocks install --server=https://luarocks.org luatest

.PHONY: selftest
selftest: ## Самопроверка на файлах-образцах
	selftest/run.sh

.PHONY: lint
lint: ## Проверить сценарии shellcheck
	shellcheck bin/tnt-mutants selftest/run.sh

.PHONY: check
check: lint selftest ## Все проверки

.PHONY: clean
clean: ## Убрать рабочие каталоги
	rm -rf var
