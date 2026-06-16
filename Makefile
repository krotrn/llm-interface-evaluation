.PHONY: up down dev logs shell-gateway shell-postgres seed bench eval eval-smoke certs lint test help

# Load environment variables from .env if present
ifneq (,$(wildcard .env))
    include .env
    export $(shell sed 's/=.*//' .env)
endif

# Default target
.DEFAULT_GOAL := help

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(firstword $(MAKEFILE_LIST)) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

up: ## Start all services in the background (production mode with Nginx)
	docker compose up -d

down: ## Stop all services and remove containers, networks, and volumes
	docker compose down -v

dev: ## Start all services in development mode (hot-reload, direct gateway port 3000 mapping, no Nginx)
	docker compose -f docker-compose.yml -f docker-compose.dev.yml up

logs: ## Tail logs for all running services
	docker compose logs -f

shell-gateway: ## Open a shell inside the gateway container
	docker compose exec gateway sh

shell-postgres: ## Connect to the Postgres database CLI inside the container
	docker compose exec postgres psql -U llmforge -d llmforge

seed: ## Seed the evaluation dataset into the PostgreSQL database
	bun run scripts/seed-eval-data.ts

bench: ## Run the k6 load tests and write results to latest.json
	@echo "Running load benchmarks..."
	# In later stages, this will run k6 scripts

eval: ## Run the full evaluation suite (150 cases)
	bun run apps/eval/src/cli.ts run

eval-smoke: ## Run a quick evaluation smoke test (subset of dataset)
	bun run apps/eval/src/cli.ts run --smoke

certs: ## Generate a self-signed SSL certificate for Nginx
	bash scripts/generate-ssl.sh

lint: ## Run linting and type checks across the monorepo
	bun x eslint . && bun x tsc --noEmit

test: ## Run unit and integration tests
	bun test
