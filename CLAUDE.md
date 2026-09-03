# recon-agent — project instructions

Invoice/payment reconciliation service: deterministic rules first, a Claude tool-use agent for what the rules cannot settle, human confirmation before anything is booked, and an evaluation harness with a CI regression gate. Owner: Arren Ting. Public portfolio project; every design decision must be one Arren can defend in an interview.

## Ground rules (apply to every agent and every session)

1. **Design before code.** `docs/design/` is the source of truth. If a change needs a new table, tool, or dependency, write or update the ADR in `docs/decisions/` first, then implement. No feature that is not in the design docs.
2. **Money is `Decimal`, stored as `NUMERIC(19,4)`.** Never `float` for amounts. Currency is an ISO 4217 code and must match across a match line.
3. **The agent proposes; a person books.** No code path lets the agent, or any automated process, write to `allocations` or change an invoice's paid status. Only `review` on an explicit human confirm does that. Treat any PR that violates this as a security defect.
4. **Rules run before the model.** The agent only ever sees payments and invoices the deterministic matcher left open.
5. **Every change to a prompt, tool, or matcher rule runs `make eval` before merge**, and the result is committed to `evals/results/`. False bookings must be 0; F1 may not drop more than the tolerance in `evals/baseline.json`.
6. **Git identity.** Commits in this repo are authored as `Arren Ting <51100940+ArrenTing@users.noreply.github.com>` (repo-local config). Never use the Vecreal address. Check `git config user.email` before the first commit of a session. Commits and pushes happen only when Arren asks.
7. **Secrets** live in `.env` (git-ignored); `.env.example` documents the keys. The Anthropic key is read by the SDK from the environment; never hard-code it, never log it.
8. **Clean code standards** (enforced by tooling where possible): ruff (format + lint, line length 100), mypy `--strict` on `src/`, pytest with coverage on `src/recon/rules` and `src/recon/review` at 95%+. Functions do one thing and fit on a screen; no magic numbers (constants module); names say what, comments say why; pure functions for matching logic, side effects only at the edges (DB, API, LLM); public functions have docstrings with an example; no `# type: ignore` without a reason.
9. **Anthropic SDK usage** follows the `claude-api` skill's Python docs, not memory. Model `claude-opus-5`, adaptive thinking, tool runner (`client.beta.messages.tool_runner`, `@beta_tool`), structured output for the final proposal. No LangChain/LangGraph in the core (see ADR-0004).
10. **Arren writes the design notes and the "how I used AI" section of the README himself.** Agents may draft technical docs; they do not write his reflections.

## Layout

```
src/recon/          package (models, rules, agent/, review, api, cli)
evals/              dataset generator, ground truth, run_eval.py, baseline.json, results/
tests/              pytest; mirrors src/ layout
docs/design/        architecture.md, database.md, tooling.md (wireframe + rationale)
docs/decisions/     ADR-NNNN-*.md
.claude/agents/     coding, testing, security, architecture
```

## Agents

- `architecture` — owns docs/design and ADRs; reviews any change that touches tables, tools, or boundaries.
- `coding` — implements against the design; small PR-sized changes; runs ruff + mypy before reporting done.
- `testing` — writes and runs tests and evals; owns `tests/` and `evals/`; reports coverage and eval deltas.
- `security` — reviews for the booking boundary, injection handling, secrets, input validation, dependency risk.

Workflow for any feature: architecture (design/ADR) → coding → testing → security → Arren reviews → commit on his word.

## Toolchain

Python 3.12 (not 3.14 — see tooling.md), `uv` for env/lock, FastAPI, Pydantic v2, SQLAlchemy 2 + Alembic, PostgreSQL 16 via Docker Compose, pytest + hypothesis, ruff, mypy, Typer, structlog, Jinja2 + htmx for the review page. Make targets: `make dev`, `make test`, `make lint`, `make eval`, `make db-up`, `make migrate`.

## Environment notes (2026-09-03)

- `uv` 0.12.9 installed via winget at `C:\Users\arren\AppData\Local\Microsoft\WinGet\Links\uv.exe`; new shells have it on PATH, this session's Git Bash needs `export PATH="/c/Users/arren/AppData/Local/Microsoft/WinGet/Links:$PATH"`.
- Locked versions: Python 3.12.9, anthropic SDK **1.3.0** (1.x line — follow the `claude-api` skill's Python docs and its `sdk-upgrade.md` conventions, not 0.x patterns), FastAPI 0.141, SQLAlchemy 2.0.52, Pydantic 2.13.
- `make check` = ruff format --check, ruff check, mypy, pytest. All green on the empty skeleton.
