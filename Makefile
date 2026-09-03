# recon-agent — developer entry points. Every target runs through uv so the lockfile is the truth.
UV ?= uv

.PHONY: help dev lint fmt type test cov eval db-up db-down migrate audit check

help:            ## list targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-10s %s\n", $$1, $$2}'

dev:             ## create/refresh the virtualenv from uv.lock (incl. dev deps)
	$(UV) sync --all-extras

fmt:             ## format code
	$(UV) run ruff format .

lint:            ## lint (no fixes)
	$(UV) run ruff format --check .
	$(UV) run ruff check .

type:            ## mypy --strict on src/
	$(UV) run mypy

test:            ## unit tests (SQLite, SDK mocked)
	$(UV) run pytest

cov:             ## tests with coverage report
	$(UV) run pytest --cov --cov-report=term-missing

eval:            ## run the evaluation harness (set RECON_EVAL_LIVE=1 to hit the real API)
	$(UV) run python -m evals.run_eval

db-up:           ## start Postgres via docker compose
	docker compose up -d db

db-down:         ## stop and remove containers (keeps the volume)
	docker compose down

migrate:         ## apply Alembic migrations
	$(UV) run alembic upgrade head

audit:           ## dependency vulnerability scan
	$(UV) run pip-audit

check: lint type test   ## what CI runs on every push
