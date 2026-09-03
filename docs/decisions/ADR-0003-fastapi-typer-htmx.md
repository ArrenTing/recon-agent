# ADR-0003 — FastAPI for the API and review page, Typer for the CLI, Jinja2 + htmx for the UI

Status: accepted · 2026-09-03 (Arren, design review)

## Context
The service needs an HTTP surface for imports, runs, and human review; a CLI for the same operations and for the eval; and a minimal review page a person can operate.

## Decision
FastAPI with Pydantic v2 models on every endpoint; a Typer CLI calling the same service layer; one Jinja2 template with htmx for confirm and reject, served by FastAPI. The API binds to 127.0.0.1 by default; no auth in v1, stated in the README.

## Alternatives considered
- Django: ORM, admin, and auth we would fight or not use in v1.
- Flask: validation and OpenAPI need add-ons FastAPI has built in.
- React/Vite frontend: doubles the work, adds a node toolchain to a Python repo, proves nothing for the target roles.
- Streamlit: fast but reads as a notebook, not a service.

## Consequences
- OpenAPI docs come free and belong in the README.
- The review page is deliberately plain; screenshots go in the README.
- Exposing the API beyond localhost requires an auth ADR first.
