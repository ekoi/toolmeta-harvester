CONFIG_FILE ?= config/config.toml

read_db_config = $(strip $(shell python3 -c 'import tomllib; from pathlib import Path; print(tomllib.loads(Path("$(CONFIG_FILE)").read_text())["database"]["$(1)"])'))

TOOL_REGISTRY_DATABASE__HOST ?= $(call read_db_config,host)
TOOL_REGISTRY_DATABASE__PORT ?= $(call read_db_config,port)
TOOL_REGISTRY_DATABASE__NAME ?= $(call read_db_config,name)
TOOL_REGISTRY_DATABASE__USER ?= $(call read_db_config,user)
TOOL_REGISTRY_DATABASE__PASSWORD ?= $(call read_db_config,password)
TOOL_REGISTRY_GITHUB__API_KEY=your_github_api_key
POSTGRES_CONTAINER=tool-registry-postgres
POSTGRES_VOLUME=tool_registry_pgdata
TOOLS_CONTAINER=ghcr.io/eosc-data-commons/tool-registry:latest
BIOBB_FLOW=src/toolmeta_harvester/flows/harvest_biobb_workflowhub_jupyter.py
TIMESTAMP := $(shell date +"%Y-%m-%d")

check-secrets:
	@test -f config/.secrets.toml || (echo "WARNING Missing config/.secrets.toml; github token might not be defined"; exit 0)

.PHONY: run-local run biobb-run biobb-run-local
run:run-local

run-local: 
	@echo "Run one of the flows in src/toolmeta_harvester/flows/"
	@echo "-----"
	ls -la src/toolmeta_harvester/flows/*.py
	@echo "-----"
	@echo "uv run src/toolmeta_harvester/flows/flow_name.py"

biobb-run:
	uv run $(BIOBB_FLOW)

biobb-run-local: print-config
	@echo "-----"
	uv run $(BIOBB_FLOW)

.PHONY: re-install install
re-install: clean sync

install: check-secrets postgres-up sync

.PHONY: clean
clean:
	rm -rf .venv uv.lock
	uv cache clean

.PHONY: sync
sync:
	uv sync
	uv pip install -e .

.PHONY: print-config
print-config:
	@echo "Resolved configuration:"
	@echo "  CONFIG_FILE=$(CONFIG_FILE)"
	@echo "  TOOL_REGISTRY_DATABASE__HOST=$(TOOL_REGISTRY_DATABASE__HOST)"
	@echo "  TOOL_REGISTRY_DATABASE__PORT=$(TOOL_REGISTRY_DATABASE__PORT)"
	@echo "  TOOL_REGISTRY_DATABASE__NAME=$(TOOL_REGISTRY_DATABASE__NAME)"
	@echo "  TOOL_REGISTRY_DATABASE__USER=$(TOOL_REGISTRY_DATABASE__USER)"
	@echo "  TOOL_REGISTRY_DATABASE__PASSWORD=$(TOOL_REGISTRY_DATABASE__PASSWORD)"
	@echo "  TOOL_REGISTRY_GITHUB__API_KEY=$(TOOL_REGISTRY_GITHUB__API_KEY)"

postgres-dump:
	@echo "Dumping 'tool_generic' table from Postgres container '$(POSTGRES_CONTAINER)' to 'tool_generic.sql'..."
	docker exec  $(POSTGRES_CONTAINER) pg_dump -U $(TOOL_REGISTRY_DATABASE__USER) -d $(TOOL_REGISTRY_DATABASE__NAME) -t tool_generic --no-owner --no-privileges -Fc > tool_generic_$(TIMESTAMP).dump

postgres-restore:
	@echo "Restoring 'tool_generic' table to Postgres container '$(POSTGRES_CONTAINER)' from 'tool_generic.sql'..."
	docker exec -i $(POSTGRES_CONTAINER) pg_restore -U $(TOOL_REGISTRY_DATABASE__USER) -d $(TOOL_REGISTRY_DATABASE__NAME) < $(shell ls -t backups/tool_generic_*.dump | head -n 1)

.PHONY: postgres-up postgres-down postgres-logs postgres-reset
postgres-up:
	# Use pgvector image which is postgres with pgvector extension pre-installed, which is required for vector search capabilities in the tool registry.
	@echo "Starting Postgres container '$(POSTGRES_CONTAINER)' on port $(TOOL_REGISTRY_DATABASE__PORT)..."
	docker run -d --rm --name $(POSTGRES_CONTAINER) \
	  	-p $(TOOL_REGISTRY_DATABASE__PORT):5432 \
	  	-e POSTGRES_DB=$(TOOL_REGISTRY_DATABASE__NAME) \
	  	-e POSTGRES_USER=$(TOOL_REGISTRY_DATABASE__USER) \
	  	-e POSTGRES_PASSWORD=$(TOOL_REGISTRY_DATABASE__PASSWORD) \
	  	-v $(POSTGRES_VOLUME):/var/lib/postgresql/data \
	  	-v $(PWD)/docker/postgres/init:/docker-entrypoint-initdb.d \
	  	pgvector/pgvector:0.8.1-pg16-trixie

postgres-down:
	@echo "Stopping and removing Postgres container '$(POSTGRES_CONTAINER)'..."
	docker stop $(POSTGRES_CONTAINER) || true
	docker rm $(POSTGRES_CONTAINER) || true

postgres-logs:
	docker logs -f $(POSTGRES_CONTAINER)

postgres-reset: postgres-down
	docker volume rm $(POSTGRES_VOLUME) || true

postgres-shell: 
	docker exec -it $(POSTGRES_CONTAINER) psql -U $(TOOL_REGISTRY_DATABASE__USER) -d $(TOOL_REGISTRY_DATABASE__NAME)

tools-build:
	docker build --network=host -t $(TOOLS_CONTAINER) .

.PHONY: tools-up tools-down tools-logs tools-shell
tools-up: tools-down tools-build
	@echo "Starting Tool Registry container..."
	docker run --name tool-registry \
		-p 8000:8000 \
		-e TOOL_REGISTRY_DATABASE__HOST=$(TOOL_REGISTRY_DATABASE__HOST) \
		-e TOOL_REGISTRY_DATABASE__PORT=$(TOOL_REGISTRY_DATABASE__PORT) \
		-e TOOL_REGISTRY_DATABASE__NAME=$(TOOL_REGISTRY_DATABASE__NAME) \
		-e TOOL_REGISTRY_DATABASE__USER=$(TOOL_REGISTRY_DATABASE__USER) \
		-e TOOL_REGISTRY_DATABASE__PASSWORD=$(TOOL_REGISTRY_DATABASE__PASSWORD) \
		-e TOOL_REGISTRY_GITHUB__API_KEY=$(TOOL_REGISTRY_GITHUB__API_KEY) \
		$(TOOLS_CONTAINER)

tools-down:
	@echo "Stopping and removing Tool Registry container..."
	docker stop tool-registry || true
	docker rm tool-registry || true

tools-logs:
	docker logs -f tool-registry

tools-shell:
	docker exec -it tool-registry /bin/sh
