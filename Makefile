# Shortcuts for the common commands. `make` on its own lists them.
VENV := .venv
BIN  := $(VENV)/bin
REFRESH ?= 0

.DEFAULT_GOAL := help
.PHONY: help setup up down build brief test docs analyses dashboard clean

help: ## List the commands
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  make %-10s %s\n", $$1, $$2}'

setup: ## Create the virtual environment and install dbt and the dashboard packages
	python3 -m venv $(VENV)
	$(BIN)/pip install -r requirements.txt

# The provided loader (raw_data/load_data.sh) appends, so running it on tables that already have data
# would add a second copy. `make up` checks first; REFRESH=1 empties the tables so they load again.
RAW_TABLES := activity activity_types deal_changes fields stages users
PSQL       := docker compose exec -T db psql -U admin -d postgres -v ON_ERROR_STOP=1 -qtA

up: ## Start Postgres and load the raw CSVs; REFRESH=1 reloads them from scratch
	docker compose up -d db
	@until docker compose exec -T db pg_isready -h localhost -U admin -q; do sleep 1; done
	@if [ "$(REFRESH)" = "1" ]; then \
		echo "REFRESH=1: emptying the raw tables so the CSVs load again"; \
		$(PSQL) -c "truncate $$(echo $(RAW_TABLES) | sed 's/ /, /g')"; \
	else \
		loaded=""; \
		for table in $(RAW_TABLES); do \
			if [ "$$($(PSQL) -c "select exists (select 1 from $$table)")" = "t" ]; then loaded="$$loaded $$table"; fi; \
		done; \
		if [ -n "$$loaded" ]; then \
			echo ""; \
			echo "ERROR: these tables already have data:$$loaded"; \
			echo "Loading the CSVs again would add a second copy of every row, so nothing was changed."; \
			echo "Postgres is running and the existing data is untouched."; \
			echo "To reload the CSVs from scratch, run:  make up REFRESH=1"; \
			echo ""; \
			exit 1; \
		fi; \
	fi
	docker compose run --rm data_loader

down: ## Stop Postgres
	docker compose down

build: ## Build the seed and all models and run all tests
	$(BIN)/dbt build

brief: ## Build only what the assignment asks for (no extensions)
	$(BIN)/dbt build --exclude tag:extension

test: ## Run the tests only
	$(BIN)/dbt test

docs: ## Generate and open the dbt docs site
	$(BIN)/dbt docs generate
	$(BIN)/dbt docs serve

analyses: ## Compile the exploration queries to target/compiled/
	$(BIN)/dbt compile -s path:analyses

dashboard: ## Start the Streamlit app
	$(BIN)/streamlit run dashboard/app.py

clean: ## Remove dbt build output
	$(BIN)/dbt clean
